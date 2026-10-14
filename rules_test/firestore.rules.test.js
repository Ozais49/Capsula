// Security rules tests. Run from this folder with `npm test`
// (starts the Firestore emulator; needs the Firebase CLI and Java).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  collection,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-capsula',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const db = (uid) =>
  uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();
const bookmarkRef = (firestore, owner, id = 'b1') =>
  doc(firestore, `users/${owner}/bookmarks/${id}`);

function validBookmark(overrides = {}) {
  const now = Timestamp.now();
  return {
    url: 'https://example.com/a',
    canonicalUrl: 'https://example.com/a',
    title: 'Example',
    source: 'website',
    sourceDomain: 'example.com',
    readingStatus: 'saved',
    archived: false,
    inInbox: true,
    createdAt: now,
    updatedAt: now,
    searchTokens: ['e', 'ex', 'example'],
    ...overrides,
  };
}

async function seed(owner, id = 'b1', data = validBookmark()) {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(bookmarkRef(ctx.firestore(), owner, id), data),
  );
}

describe('owner access', () => {
  test('can create, read, update and delete their bookmark', async () => {
    const alice = db('alice');
    await assertSucceeds(setDoc(bookmarkRef(alice, 'alice'), validBookmark()));
    await assertSucceeds(getDoc(bookmarkRef(alice, 'alice')));
    await assertSucceeds(getDocs(collection(alice, 'users/alice/bookmarks')));
    await assertSucceeds(
      updateDoc(bookmarkRef(alice, 'alice'), {
        readingStatus: 'read',
        updatedAt: Timestamp.now(),
      }),
    );
    await assertSucceeds(deleteDoc(bookmarkRef(alice, 'alice')));
  });

  test('can store optional description and image', async () => {
    await assertSucceeds(
      setDoc(
        bookmarkRef(db('alice'), 'alice'),
        validBookmark({ description: 'd', imageUrl: 'https://img.example.com/x.png' }),
      ),
    );
  });
});

describe('cross-user isolation', () => {
  beforeEach(() => seed('bob'));

  test('User A cannot read User B\'s bookmark', async () => {
    await assertFails(getDoc(bookmarkRef(db('alice'), 'bob')));
  });

  test('User A cannot list User B\'s bookmarks', async () => {
    await assertFails(getDocs(collection(db('alice'), 'users/bob/bookmarks')));
  });

  test('User A cannot modify User B\'s bookmark', async () => {
    await assertFails(
      updateDoc(bookmarkRef(db('alice'), 'bob'), { title: 'hacked' }),
    );
  });

  test('User A cannot delete User B\'s bookmark', async () => {
    await assertFails(deleteDoc(bookmarkRef(db('alice'), 'bob')));
  });

  test('User A cannot create bookmarks in User B\'s library', async () => {
    await assertFails(setDoc(bookmarkRef(db('alice'), 'bob', 'new'), validBookmark()));
  });

  test('signed-out users cannot read or write anything', async () => {
    const anon = db(null);
    await assertFails(getDoc(bookmarkRef(anon, 'bob')));
    await assertFails(setDoc(bookmarkRef(anon, 'bob', 'new'), validBookmark()));
  });
});

describe('other paths are closed', () => {
  test('cannot read or write outside users/{uid}/bookmarks', async () => {
    const alice = db('alice');
    await assertFails(setDoc(doc(alice, 'users/alice'), { name: 'x' }));
    await assertFails(setDoc(doc(alice, 'users/alice/other/x'), { a: 1 }));
    await assertFails(getDoc(doc(alice, 'public/anything')));
  });
});

describe('bookmark validation', () => {
  const rejects = (overrides) =>
    assertFails(setDoc(bookmarkRef(db('alice'), 'alice'), validBookmark(overrides)));

  test('rejects non-web URLs', async () => {
    await rejects({ url: 'javascript:alert(1)' });
    await rejects({ url: 'ftp://example.com' });
  });

  test('rejects unknown fields', async () => {
    await rejects({ userId: 'bob' });
    await rejects({ isPublic: true });
  });

  test('rejects missing required fields', async () => {
    const data = validBookmark();
    delete data.canonicalUrl;
    await assertFails(setDoc(bookmarkRef(db('alice'), 'alice'), data));
  });

  test('rejects wrong types and invalid values', async () => {
    await rejects({ archived: 'yes' });
    await rejects({ readingStatus: 'deleted' });
    await rejects({ title: 42 });
    await rejects({ createdAt: '2026-01-01' });
    await rejects({ searchTokens: 'abc' });
  });

  test('rejects oversized values', async () => {
    await rejects({ title: 'x'.repeat(1001) });
    await rejects({ url: `https://example.com/${'x'.repeat(5000)}` });
    await rejects({ searchTokens: Array.from({ length: 401 }, (_, i) => `t${i}`) });
  });

  test('rejects dates far in the future', async () => {
    const future = Timestamp.fromMillis(Date.now() + 3 * 24 * 3600 * 1000);
    await rejects({ createdAt: future, updatedAt: future });
  });

  test('allows imported dates in the past', async () => {
    await assertSucceeds(
      setDoc(
        bookmarkRef(db('alice'), 'alice'),
        validBookmark({ createdAt: Timestamp.fromMillis(Date.UTC(2015, 0, 1)) }),
      ),
    );
  });
});

describe('immutable fields', () => {
  beforeEach(() => seed('alice'));

  test('cannot change createdAt, url or canonicalUrl', async () => {
    const ref = bookmarkRef(db('alice'), 'alice');
    await assertFails(updateDoc(ref, { createdAt: Timestamp.fromMillis(0) }));
    await assertFails(updateDoc(ref, { url: 'https://evil.example.com' }));
    await assertFails(updateDoc(ref, { canonicalUrl: 'https://other.example.com' }));
  });
});
