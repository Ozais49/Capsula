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

describe('tags and collections', () => {
  const labelRef = (firestore, owner, kind = 'tags', id = 'l1') =>
    doc(firestore, `users/${owner}/${kind}/${id}`);
  const validLabel = (overrides = {}) => ({
    name: 'AI',
    createdAt: Timestamp.now(),
    ...overrides,
  });

  test('owner can create, rename, list and delete', async () => {
    const alice = db('alice');
    for (const kind of ['tags', 'collections']) {
      await assertSucceeds(setDoc(labelRef(alice, 'alice', kind), validLabel()));
      await assertSucceeds(updateDoc(labelRef(alice, 'alice', kind), { name: 'ML' }));
      await assertSucceeds(getDocs(collection(alice, `users/alice/${kind}`)));
      await assertSucceeds(deleteDoc(labelRef(alice, 'alice', kind)));
    }
  });

  test('User A cannot read, change or delete User B\'s labels', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(labelRef(ctx.firestore(), 'bob'), validLabel()),
    );
    const alice = db('alice');
    await assertFails(getDoc(labelRef(alice, 'bob')));
    await assertFails(getDocs(collection(alice, 'users/bob/tags')));
    await assertFails(updateDoc(labelRef(alice, 'bob'), { name: 'x' }));
    await assertFails(deleteDoc(labelRef(alice, 'bob')));
    await assertFails(setDoc(labelRef(alice, 'bob', 'tags', 'new'), validLabel()));
  });

  test('rejects invalid labels and unknown subcollections', async () => {
    const alice = db('alice');
    await assertFails(setDoc(labelRef(alice, 'alice'), validLabel({ name: '' })));
    await assertFails(setDoc(labelRef(alice, 'alice'), validLabel({ name: 'x'.repeat(51) })));
    await assertFails(setDoc(labelRef(alice, 'alice'), validLabel({ color: 'red' })));
    await assertFails(setDoc(labelRef(alice, 'alice', 'secrets'), validLabel()));
  });

  test('bookmarks accept tag and collection IDs within limits', async () => {
    const ref = bookmarkRef(db('alice'), 'alice');
    await assertSucceeds(setDoc(ref, validBookmark({ tagIds: ['t1'], collectionIds: ['c1'] })));
    await assertFails(setDoc(ref, validBookmark({ tagIds: 'not-a-list' })));
    await assertFails(
      setDoc(ref, validBookmark({ tagIds: Array.from({ length: 101 }, (_, i) => `t${i}`) })),
    );
  });
});

describe('import provenance', () => {
  test('accepts importedFrom and importedAt', async () => {
    await assertSucceeds(
      setDoc(
        bookmarkRef(db('alice'), 'alice'),
        validBookmark({ importedFrom: 'Raindrop', importedAt: Timestamp.now() }),
      ),
    );
  });

  test('rejects malformed provenance', async () => {
    const ref = bookmarkRef(db('alice'), 'alice');
    await assertFails(setDoc(ref, validBookmark({ importedFrom: 'x'.repeat(51) })));
    await assertFails(setDoc(ref, validBookmark({ importedFrom: 7 })));
    await assertFails(setDoc(ref, validBookmark({ importedAt: '2024-01-01' })));
  });

  test('a batch of imported bookmarks writes as the owner only', async () => {
    const { writeBatch } = await import('firebase/firestore');
    const alice = db('alice');
    const own = writeBatch(alice);
    own.set(bookmarkRef(alice, 'alice', 'i1'), validBookmark({ importedFrom: 'Chrome' }));
    own.set(bookmarkRef(alice, 'alice', 'i2'), validBookmark({ importedFrom: 'Chrome' }));
    await assertSucceeds(own.commit());

    const mixed = writeBatch(alice);
    mixed.set(bookmarkRef(alice, 'alice', 'i3'), validBookmark());
    mixed.set(bookmarkRef(alice, 'bob', 'i4'), validBookmark());
    await assertFails(mixed.commit());
  });
});

describe('favorites and nested collections', () => {
  test('favorite must be a boolean', async () => {
    const ref = bookmarkRef(db('alice'), 'alice');
    await assertSucceeds(setDoc(ref, validBookmark({ favorite: true })));
    await assertFails(setDoc(ref, validBookmark({ favorite: 'yes' })));
  });

  test('collections may name a parent', async () => {
    const alice = db('alice');
    const ref = doc(alice, 'users/alice/collections/child');
    await assertSucceeds(setDoc(ref, { name: 'Child', parentId: 'parent', createdAt: Timestamp.now() }));
    await assertSucceeds(updateDoc(ref, { parentId: 'other' }));
    await assertFails(setDoc(ref, { name: 'Child', parentId: 42, createdAt: Timestamp.now() }));
  });
});

describe('notes and highlights', () => {
  const hRef = (firestore, owner, id = 'h1') =>
    doc(firestore, `users/${owner}/highlights/${id}`);
  const validHighlight = (overrides = {}) => ({
    bookmarkId: 'b1',
    text: 'An important passage',
    color: 'yellow',
    createdAt: Timestamp.now(),
    ...overrides,
  });

  test('bookmark notes are optional strings', async () => {
    const ref = bookmarkRef(db('alice'), 'alice');
    await assertSucceeds(setDoc(ref, validBookmark({ note: 'Remember this' })));
    await assertFails(setDoc(ref, validBookmark({ note: 5 })));
    await assertFails(setDoc(ref, validBookmark({ note: 'x'.repeat(10001) })));
  });

  test('owner can create, annotate and delete highlights', async () => {
    const ref = hRef(db('alice'), 'alice');
    await assertSucceeds(setDoc(ref, validHighlight()));
    await assertSucceeds(updateDoc(ref, { note: 'Why it matters', color: 'green' }));
    await assertFails(updateDoc(ref, { text: 'Rewritten' }));
    await assertSucceeds(deleteDoc(ref));
  });

  test('rejects invalid highlights and other users', async () => {
    const alice = db('alice');
    await assertFails(setDoc(hRef(alice, 'alice'), validHighlight({ text: '' })));
    await assertFails(setDoc(hRef(alice, 'alice'), validHighlight({ color: 'red' })));
    await assertFails(setDoc(hRef(alice, 'alice'), validHighlight({ extra: 1 })));
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(hRef(ctx.firestore(), 'bob'), validHighlight()),
    );
    await assertFails(getDoc(hRef(alice, 'bob')));
    await assertFails(deleteDoc(hRef(alice, 'bob')));
  });
});

describe('public links', () => {
  const cRef = (firestore, id = 'c1') => doc(firestore, `users/alice/collections/${id}`);

  test('clients can\'t set or change a share ID', async () => {
    const alice = db('alice');
    await assertFails(setDoc(cRef(alice), { name: 'Work', shareId: 'mine', createdAt: Timestamp.now() }));

    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(cRef(ctx.firestore()), { name: 'Work', shareId: 'server-set', createdAt: Timestamp.now() }),
    );
    await assertFails(updateDoc(cRef(alice), { shareId: 'hijacked' }));
    await assertSucceeds(updateDoc(cRef(alice), { name: 'Renamed' }));
  });

  test('share records are server-only', async () => {
    await assertFails(getDoc(doc(db('alice'), 'publicShares/anything')));
    await assertFails(setDoc(doc(db('alice'), 'publicShares/x'), { uid: 'alice' }));
    await assertFails(getDoc(doc(db(null), 'publicShares/anything')));
  });
});

describe('content type', () => {
  test('type must be a known value', async () => {
    const ref = bookmarkRef(db('alice'), 'alice');
    await assertSucceeds(setDoc(ref, validBookmark({ type: 'video' })));
    await assertFails(setDoc(ref, validBookmark({ type: 'podcast' })));
  });
});

describe('content type', () => {
  test('type must be a known value', async () => {
    const ref = bookmarkRef(db('alice'), 'alice');
    await assertSucceeds(setDoc(ref, validBookmark({ type: 'video' })));
    await assertFails(setDoc(ref, validBookmark({ type: 'podcast' })));
  });
});

describe('reminders', () => {
  test('remindAt must be a timestamp', async () => {
    const ref = bookmarkRef(db('alice'), 'alice');
    await assertSucceeds(setDoc(ref, validBookmark({ remindAt: Timestamp.now() })));
    await assertFails(setDoc(ref, validBookmark({ remindAt: 'tomorrow' })));
  });
});
