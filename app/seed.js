'use strict';

// Seeds Maratón with four demo users and their shows.
// Run locally:      docker compose run --rm app node seed.js
// Run in the cluster: kubectl exec -n maraton deploy/maraton -- node seed.js
//
// Re-running is safe: it removes the demo users (and their shows) first.
// The show picks are placeholders. Swap in your real favorites!

const bcrypt = require('bcryptjs');
const { connect, close } = require('./src/db');

const DEMO_PASSWORD = process.env.SEED_PASSWORD || 'maraton-demo';

const demo = [
  {
    email: 'patricia@maraton.demo',
    displayName: 'Patricia',
    shows: [
      { title: 'Severance', platform: 'Apple TV+', genre: 'Thriller', year: 2022, status: 'Watching', progress: { season: 2, episode: 7 }, rating: 4.5, favorite: true, review: 'The most unsettling office I have ever wanted to work in.' },
      { title: 'Fleabag', platform: 'Prime Video', genre: 'Comedy', year: 2016, totalSeasons: 2, status: 'Completed', progress: { season: 2, episode: 6 }, rating: 5, favorite: true, review: 'Twelve perfect episodes. Not one wasted minute.' },
      { title: 'Gilmore Girls', platform: 'Netflix', genre: 'Comedy-drama', year: 2000, totalSeasons: 7, status: 'Completed', progress: { season: 7, episode: 22 }, rating: 4.5, favorite: true, review: 'Comfort rewatch, every single fall.' },
      { title: 'The Bear', platform: 'Hulu', genre: 'Drama', year: 2022, status: 'Completed', progress: { season: 1, episode: 8 }, rating: 4.5, favorite: true, review: 'Season one is the most stressful half hour on TV, in the best way.' },
      { title: 'Narcos: México', platform: 'Netflix', genre: 'Crime', year: 2018, totalSeasons: 3, status: 'Watching', progress: { season: 1, episode: 4 }, rating: 4, favorite: false, review: '' },
      { title: 'Club de Cuervos', platform: 'Netflix', genre: 'Comedy', year: 2015, totalSeasons: 4, status: 'Completed', progress: { season: 4, episode: 10 }, rating: 4, favorite: false, review: 'Chava Iglesias is a national treasure.' },
      { title: 'Succession', platform: 'HBO Max', genre: 'Drama', year: 2018, totalSeasons: 4, status: 'Plan to Watch', progress: { season: 1, episode: 0 }, rating: null, favorite: false, review: '' },
    ],
  },
  {
    email: 'sofia@maraton.demo',
    displayName: 'Sofía',
    shows: [
      { title: 'Abbott Elementary', platform: 'Hulu', genre: 'Comedy', year: 2021, status: 'Watching', progress: { season: 3, episode: 2 }, rating: 4.5, favorite: true, review: 'Janine deserves a raise.' },
      { title: 'La Casa de Papel', platform: 'Netflix', genre: 'Thriller', year: 2017, totalSeasons: 5, status: 'Completed', progress: { season: 5, episode: 10 }, rating: 4, favorite: true, review: '' },
    ],
  },
  {
    email: 'diego@maraton.demo',
    displayName: 'Diego',
    shows: [
      { title: 'The Last of Us', platform: 'HBO Max', genre: 'Drama', year: 2023, status: 'Watching', progress: { season: 1, episode: 3 }, rating: 5, favorite: true, review: 'Episode three wrecked me.' },
      { title: 'Breaking Bad', platform: 'Netflix', genre: 'Crime', year: 2008, totalSeasons: 5, status: 'Completed', progress: { season: 5, episode: 16 }, rating: 5, favorite: true, review: '' },
      { title: 'Lost', platform: 'Hulu', genre: 'Mystery', year: 2004, totalSeasons: 6, status: 'Dropped', progress: { season: 3, episode: 5 }, rating: 3, favorite: false, review: 'Came for the island, left during the cages.' },
    ],
  },
  {
    email: 'mariana@maraton.demo',
    displayName: 'Mariana',
    shows: [
      { title: 'Ted Lasso', platform: 'Apple TV+', genre: 'Comedy', year: 2020, totalSeasons: 3, status: 'Completed', progress: { season: 3, episode: 12 }, rating: 4.5, favorite: true, review: 'Believe.' },
      { title: 'The Crown', platform: 'Netflix', genre: 'Drama', year: 2016, totalSeasons: 6, status: 'Plan to Watch', progress: { season: 1, episode: 0 }, rating: null, favorite: false, review: '' },
    ],
  },
];

async function main() {
  const uri = process.env.MONGODB_URI;
  if (!uri) throw new Error('MONGODB_URI is required');

  const db = await connect(uri);
  const users = db.collection('users');
  const shows = db.collection('shows');
  const passwordHash = await bcrypt.hash(DEMO_PASSWORD, 10);

  for (const person of demo) {
    const existing = await users.findOne({ email: person.email });
    if (existing) {
      await shows.deleteMany({ userId: existing._id });
      await users.deleteOne({ _id: existing._id });
    }

    const now = new Date();
    const { insertedId } = await users.insertOne({
      email: person.email,
      displayName: person.displayName,
      passwordHash,
      createdAt: now,
    });

    await shows.insertMany(
      person.shows.map((show, i) => ({
        totalSeasons: null,
        ...show,
        userId: insertedId,
        createdAt: now,
        updatedAt: new Date(now.getTime() - i * 60000), // keeps a stable "recently updated" order
      }))
    );
    console.log(`Seeded ${person.displayName} (${person.email}) with ${person.shows.length} shows`);
  }

  console.log(`Done. Every demo account uses the password: ${DEMO_PASSWORD}`);
}

main()
  .catch((err) => {
    console.error('Seeding failed:', err.message);
    process.exitCode = 1;
  })
  .finally(() => close());
