const NAME = 'voicestudio';
let _db;

function open() {
  if (_db) return Promise.resolve(_db);
  return new Promise((res, rej) => {
    const r = indexedDB.open(NAME, 1);
    r.onupgradeneeded = () => {
      const d = r.result;
      d.createObjectStore('meta', { keyPath: 'id' });
      d.createObjectStore('audio', { keyPath: 'id' });
    };
    r.onsuccess = () => { _db = r.result; res(_db); };
    r.onerror = () => rej(r.error);
  });
}

const wrap = (req) => new Promise((res, rej) => { req.onsuccess = () => res(req.result); req.onerror = () => rej(req.error); });

export async function saveProject(meta, wav) {
  const db = await open();
  const tx = db.transaction(['meta', 'audio'], 'readwrite');
  tx.objectStore('meta').put(meta);
  if (wav) tx.objectStore('audio').put({ id: meta.id, wav });
  return new Promise((res, rej) => { tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
}
export async function listProjects() {
  const db = await open();
  const all = await wrap(db.transaction('meta').objectStore('meta').getAll());
  return all.sort((a, b) => b.updated - a.updated);
}
export async function getMeta(id) { const db = await open(); return wrap(db.transaction('meta').objectStore('meta').get(id)); }
export async function getAudio(id) {
  const db = await open();
  const r = await wrap(db.transaction('audio').objectStore('audio').get(id));
  return r && r.wav;
}
export async function deleteProject(id) {
  const db = await open();
  const tx = db.transaction(['meta', 'audio'], 'readwrite');
  tx.objectStore('meta').delete(id);
  tx.objectStore('audio').delete(id);
  return new Promise((res, rej) => { tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
}
