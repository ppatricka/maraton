'use strict';

const { MongoClient } = require('mongodb');

let client;
let db;

// Connects using the MONGODB_URI passed in from a Kubernetes environment variable.
// The database name comes from the URI path (e.g. .../maraton?authSource=admin)
// unless MONGODB_DB overrides it.
async function connect(uri) {
  client = new MongoClient(uri, { serverSelectionTimeoutMS: 10000, appName: 'maraton' });
  await client.connect();
  db = client.db(process.env.MONGODB_DB || undefined);

  await db.collection('users').createIndex({ email: 1 }, { unique: true });
  await db.collection('shows').createIndex({ userId: 1, updatedAt: -1 });
  return db;
}

function getDb() {
  if (!db) throw new Error('Database not connected');
  return db;
}

async function close() {
  if (client) await client.close();
}

module.exports = { connect, getDb, close };
