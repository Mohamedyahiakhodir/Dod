let seq = 0;

/** Run a DSP job in a dedicated worker. Returns { promise, cancel }. */
export function runJob(type, data, onProgress) {
  const id = ++seq;
  const w = new Worker('js/worker.js');
  let rej;
  const promise = new Promise((resolve, reject) => {
    rej = reject;
    w.onmessage = (e) => {
      const m = e.data;
      if (m.id !== id) return;
      if (m.progress != null) onProgress && onProgress(m.progress);
      else if (m.error) { w.terminate(); reject(new Error(m.error)); }
      else { w.terminate(); resolve(m.chs); }
    };
    w.onerror = (e) => { w.terminate(); reject(new Error(e.message || 'worker error')); };
    const chs = data.chs.map((c) => c.slice());
    const transfer = chs.map((c) => c.buffer);
    const msg = { ...data, chs, id, type };
    if (data.profile) { msg.profile = data.profile.slice(); transfer.push(msg.profile.buffer); }
    w.postMessage(msg, transfer);
  });
  return {
    promise,
    cancel() { w.terminate(); rej(Object.assign(new Error('cancelled'), { cancelled: true })); },
  };
}
