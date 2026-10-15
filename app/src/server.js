'use strict';

const path = require('path');
const crypto = require('crypto');
const express = require('express');
const cookieSession = require('cookie-session');
const bcrypt = require('bcryptjs');
const { ObjectId } = require('mongodb');
const { connect, getDb, close } = require('./db');

// ---------------------------------------------------------------------------
// Configuration (all from environment variables set in Kubernetes)
// ---------------------------------------------------------------------------
const PORT = Number(process.env.PORT) || 3000;
const MONGODB_URI = process.env.MONGODB_URI;
if (!MONGODB_URI) {
  console.error('MONGODB_URI is required (set it as a Kubernetes environment variable).');
  process.exit(1);
}

let SESSION_SECRET = process.env.SESSION_SECRET;
if (!SESSION_SECRET) {
  SESSION_SECRET = crypto.randomBytes(32).toString('hex');
  console.warn('SESSION_SECRET not set; using a random one (sessions reset when the pod restarts).');
}

const STATUSES = ['Watching', 'Plan to Watch', 'Completed', 'Dropped'];
// How each status is labelled on the diary page
const STATUS_LABELS = { Watching: 'Mid-binge', 'Plan to Watch': 'On the list', Completed: 'Finished it', Dropped: 'Gave up' };

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function stars(rating) {
  if (rating == null) return '';
  const full = Math.floor(rating);
  return '★'.repeat(full) + (rating - full >= 0.5 ? '½' : '');
}

// Inputs are always coerced to plain strings/numbers before they reach MongoDB,
// so a request can never smuggle in a query operator (NoSQL injection).
function str(value, max) {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}

function int(value, min, max) {
  const n = parseInt(value, 10);
  if (Number.isNaN(n)) return null;
  return Math.min(Math.max(n, min), max);
}

function parseRating(value) {
  const n = parseFloat(value);
  if (Number.isNaN(n)) return null;
  return Math.min(Math.max(Math.round(n * 2) / 2, 0.5), 5);
}

function toObjectId(id) {
  return typeof id === 'string' && ObjectId.isValid(id) && String(new ObjectId(id)) === id
    ? new ObjectId(id)
    : null;
}

function currentUserId(req) {
  return new ObjectId(req.session.user.id);
}

function showFromBody(body) {
  return {
    title: str(body.title, 120),
    platform: str(body.platform, 60),
    genre: str(body.genre, 40),
    year: int(body.year, 1940, 2100),
    totalSeasons: int(body.totalSeasons, 1, 100),
    status: STATUSES.includes(body.status) ? body.status : 'Plan to Watch',
    progress: {
      season: int(body.season, 1, 100) || 1,
      episode: int(body.episode, 0, 500) || 0,
    },
    rating: body.rating ? parseRating(body.rating) : null,
    review: str(body.review, 1000),
    favorite: body.favorite === 'on',
  };
}

const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

function requireAuth(req, res, next) {
  if (!res.locals.user) return res.redirect('/login');
  next();
}

function notFound(res) {
  return res.status(404).render('error', {
    pageTitle: 'Not found',
    title: 'Not found',
    message: 'That page wandered off. Maybe it got cancelled after one season.',
  });
}

// ---------------------------------------------------------------------------
// App setup
// ---------------------------------------------------------------------------
const app = express();
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, '..', 'views'));
app.disable('x-powered-by');
app.set('trust proxy', 1); // runs behind the cloud load balancer + ingress

app.use(express.urlencoded({ extended: false, limit: '20kb' }));
app.use(express.static(path.join(__dirname, '..', 'public'), { maxAge: '1h' }));
app.use(
  cookieSession({
    name: 'maraton_session',
    keys: [SESSION_SECRET],
    maxAge: 7 * 24 * 60 * 60 * 1000,
    httpOnly: true,
    sameSite: 'lax',
  })
);

app.use((req, res, next) => {
  res.locals.user = req.session && req.session.user ? req.session.user : null;
  res.locals.stars = stars;
  res.locals.statusLabels = STATUS_LABELS;
  res.locals.path = req.path;
  next();
});

// ---------------------------------------------------------------------------
// Health checks for Kubernetes probes
// ---------------------------------------------------------------------------
app.get('/healthz', (req, res) => res.type('text').send('ok'));

app.get(
  '/readyz',
  asyncHandler(async (req, res) => {
    try {
      await getDb().command({ ping: 1 });
      res.type('text').send('ready');
    } catch (err) {
      res.status(503).type('text').send('database unavailable');
    }
  })
);

// ---------------------------------------------------------------------------
// Accounts
// ---------------------------------------------------------------------------
app.get('/login', (req, res) => {
  if (res.locals.user) return res.redirect('/');
  res.render('login', { pageTitle: 'Sign in', error: null, email: '' });
});

app.post(
  '/login',
  asyncHandler(async (req, res) => {
    const email = str(req.body.email, 200).toLowerCase();
    const password = typeof req.body.password === 'string' ? req.body.password : '';
    const user = await getDb().collection('users').findOne({ email });

    if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
      return res.status(401).render('login', {
        pageTitle: 'Sign in',
        error: "That email and password combination didn't match.",
        email,
      });
    }

    req.session.user = { id: String(user._id), displayName: user.displayName, email: user.email };
    res.redirect('/');
  })
);

app.get('/register', (req, res) => {
  if (res.locals.user) return res.redirect('/');
  res.render('register', { pageTitle: 'Create account', error: null, email: '', displayName: '' });
});

app.post(
  '/register',
  asyncHandler(async (req, res) => {
    const email = str(req.body.email, 200).toLowerCase();
    const displayName = str(req.body.displayName, 40);
    const password = typeof req.body.password === 'string' ? req.body.password : '';

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !displayName || password.length < 8) {
      return res.status(400).render('register', {
        pageTitle: 'Create account',
        error: 'Use a valid email, a display name, and a password of at least 8 characters.',
        email,
        displayName,
      });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    try {
      const result = await getDb()
        .collection('users')
        .insertOne({ email, displayName, passwordHash, createdAt: new Date() });
      req.session.user = { id: String(result.insertedId), displayName, email };
      res.redirect('/');
    } catch (err) {
      if (err.code === 11000) {
        return res.status(409).render('register', {
          pageTitle: 'Create account',
          error: 'An account with that email already exists.',
          email,
          displayName,
        });
      }
      throw err;
    }
  })
);

app.post('/logout', (req, res) => {
  req.session = null;
  res.redirect('/login');
});

// ---------------------------------------------------------------------------
// Diary
// ---------------------------------------------------------------------------
app.get(
  '/',
  requireAuth,
  asyncHandler(async (req, res) => {
    const shows = await getDb()
      .collection('shows')
      .find({ userId: currentUserId(req) })
      .sort({ updatedAt: -1 })
      .toArray();

    const favorites = shows
      .filter((s) => s.favorite)
      .sort((a, b) => (b.rating || 0) - (a.rating || 0))
      .slice(0, 4);
    const byStatus = Object.fromEntries(STATUSES.map((status) => [status, shows.filter((s) => s.status === status)]));

    res.render('home', { pageTitle: 'Diary', favorites, byStatus, statuses: STATUSES, total: shows.length });
  })
);

async function findOwnedShow(req) {
  const id = toObjectId(req.params.id);
  if (!id) return null;
  return getDb().collection('shows').findOne({ _id: id, userId: currentUserId(req) });
}

function renderForm(res, { show, action, heading, error, status = 200 }) {
  res.status(status).render('form', { pageTitle: heading, show, statuses: STATUSES, action, heading, error });
}

app.get('/shows/new', requireAuth, (req, res) => {
  renderForm(res, {
    show: { status: 'Watching', progress: { season: 1, episode: 0 } },
    action: '/shows',
    heading: 'Log a show',
    error: null,
  });
});

app.post(
  '/shows',
  requireAuth,
  asyncHandler(async (req, res) => {
    const show = showFromBody(req.body);
    if (!show.title) {
      return renderForm(res, { show, action: '/shows', heading: 'Log a show', error: 'Every show needs a title.', status: 400 });
    }
    const now = new Date();
    await getDb()
      .collection('shows')
      .insertOne({ ...show, userId: currentUserId(req), createdAt: now, updatedAt: now });
    res.redirect('/');
  })
);

app.get(
  '/shows/:id/edit',
  requireAuth,
  asyncHandler(async (req, res) => {
    const show = await findOwnedShow(req);
    if (!show) return notFound(res);
    renderForm(res, { show, action: `/shows/${show._id}`, heading: `Edit ${show.title}`, error: null });
  })
);

app.post(
  '/shows/:id',
  requireAuth,
  asyncHandler(async (req, res) => {
    const existing = await findOwnedShow(req);
    if (!existing) return notFound(res);

    const show = showFromBody(req.body);
    if (!show.title) {
      return renderForm(res, {
        show: { ...show, _id: existing._id },
        action: `/shows/${existing._id}`,
        heading: `Edit ${existing.title}`,
        error: 'Every show needs a title.',
        status: 400,
      });
    }

    await getDb()
      .collection('shows')
      .updateOne({ _id: existing._id }, { $set: { ...show, updatedAt: new Date() } });
    res.redirect('/');
  })
);

// "+1 ep": the quickest way to prove writes are landing in MongoDB during the demo.
app.post(
  '/shows/:id/next',
  requireAuth,
  asyncHandler(async (req, res) => {
    const existing = await findOwnedShow(req);
    if (!existing) return notFound(res);

    const set = { updatedAt: new Date() };
    if (existing.status === 'Plan to Watch') set.status = 'Watching';
    await getDb()
      .collection('shows')
      .updateOne({ _id: existing._id }, { $inc: { 'progress.episode': 1 }, $set: set });
    res.redirect('/');
  })
);

app.post(
  '/shows/:id/delete',
  requireAuth,
  asyncHandler(async (req, res) => {
    const existing = await findOwnedShow(req);
    if (!existing) return notFound(res);
    await getDb().collection('shows').deleteOne({ _id: existing._id });
    res.redirect('/');
  })
);

app.get(
  '/stats',
  requireAuth,
  asyncHandler(async (req, res) => {
    const [result] = await getDb()
      .collection('shows')
      .aggregate([
        { $match: { userId: currentUserId(req) } },
        {
          $facet: {
            totals: [
              {
                $group: {
                  _id: null,
                  shows: { $sum: 1 },
                  favorites: { $sum: { $cond: ['$favorite', 1, 0] } },
                  avgRating: { $avg: '$rating' },
                },
              },
            ],
            byStatus: [{ $group: { _id: '$status', count: { $sum: 1 } } }],
            byGenre: [
              { $match: { genre: { $nin: ['', null] } } },
              { $group: { _id: '$genre', count: { $sum: 1 } } },
              { $sort: { count: -1, _id: 1 } },
              { $limit: 5 },
            ],
            byPlatform: [
              { $match: { platform: { $nin: ['', null] } } },
              { $group: { _id: '$platform', count: { $sum: 1 } } },
              { $sort: { count: -1, _id: 1 } },
              { $limit: 5 },
            ],
          },
        },
      ])
      .toArray();

    const totals = result.totals[0] || { shows: 0, favorites: 0, avgRating: null };
    const statusCounts = Object.fromEntries(STATUSES.map((s) => [s, 0]));
    result.byStatus.forEach((row) => {
      if (row._id in statusCounts) statusCounts[row._id] = row.count;
    });

    res.render('stats', {
      pageTitle: 'Stats',
      totals,
      statusCounts,
      statuses: STATUSES,
      genres: result.byGenre,
      platforms: result.byPlatform,
    });
  })
);

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------
app.use((req, res) => notFound(res));

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).render('error', {
    pageTitle: 'Something broke',
    title: 'Something broke',
    message: 'Our side had a problem loading that. Try again in a moment.',
  });
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
connect(MONGODB_URI)
  .then(() => {
    // Never log MONGODB_URI: it contains the database password.
    const server = app.listen(PORT, () => console.log(`Maratón listening on port ${PORT}`));
    const shutdown = () => server.close(() => close().finally(() => process.exit(0)));
    process.on('SIGTERM', shutdown);
    process.on('SIGINT', shutdown);
  })
  .catch((err) => {
    console.error('Could not connect to MongoDB:', err.message);
    process.exit(1);
  });
