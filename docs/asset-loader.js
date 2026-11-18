/* Bounded, resumable transport shared by desktop and touch entry points. */
(() => {
  class ToyroomAssets {
    constructor(manifest, onProgress = () => {}) {
      this.manifest = manifest;
      this.onProgress = onProgress;
      this.fetch = globalThis.fetch.bind(globalThis);
      this.total = Object.values(manifest).reduce((n, a) => n + a.bytes, 0);
      this.loaded = new Map();
      this.active = 0;
      this.waiters = [];
      this.groups = new Set();
      this.cacheBroken = false;
      this.saves = new Set();
      this.cancelled = false;
      this.stats = {requests:0,retries:0,cacheHits:0,cacheFailures:0,decoders:{}};
      this.cache = this.openCache();
    }
    async limited(work) {
      if (this.active >= 3) await new Promise(resolve => this.waiters.push(resolve));
      else this.active++;
      try { return await work(); }
      finally {
        const next = this.waiters.shift();
        if (next) next(); else this.active--;
      }
    }
    async deadline(promise, ms = 10000) {
      let timer;
      try { return await Promise.race([promise, new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error("Storage timeout")), ms);
      })]); } finally { clearTimeout(timer); }
    }
    async openCache() {
      try { return globalThis.caches ? await this.deadline(caches.open("toyroom-assets-v1"), 3000) : null; }
      catch (_) { this.cacheBroken = true; return null; }
    }
    track(part, bytes, cached = false) {
      this.loaded.set(part.path, Math.min(part.bytes, bytes));
      const loaded = [...this.loaded.values()].reduce((a, b) => a + b, 0);
      this.onProgress({ loaded, total: this.total, cached });
    }
    async allCached() {
      const cache = await this.cache;
      if (!cache) return false;
      try {
        const parts = Object.values(this.manifest).flatMap(a => a.parts);
        // Metadata only: opening all 69 Response bodies before Play can read the
        // entire 271 MiB cache on some browsers. Each part is validated on use.
        const keys = new Set((await this.deadline(cache.keys())).map(k => k.url));
        return parts.every(p => keys.has(new URL(p.path, location.href).href));
      } catch (_) { return false; }
    }
    save(cache, part, bytes) {
      // Saving is optional and off the download/decode critical path. Bound the
      // outstanding bodies to 12 MiB instead of queuing the whole game in RAM.
      if (!cache || this.cacheBroken || this.saves.size >= 3) return;
      const job = this.deadline(cache.put(part.path, new Response(bytes, {headers:{
        "Content-Type":"application/octet-stream", "Content-Length":String(bytes.length),
      }}))).catch(() => {this.cacheBroken = true; this.stats.cacheFailures++;});
      this.saves.add(job); job.finally(() => this.saves.delete(job));
    }
    async flushSaves() { await Promise.all([...this.saves]); }
    cancel() { this.cancelled = true; for (const group of this.groups) group.cancel(); }
    async prune() {
      const cache = await this.cache;
      if (!cache) return;
      try {
        const wanted = new Set(Object.values(this.manifest).flatMap(a => a.parts.map(p => new URL(p.path, location.href).href)));
        const keys = await this.deadline(cache.keys());
        await this.deadline(Promise.all(keys.filter(k => !wanted.has(k.url)).map(k => cache.delete(k))));
      } catch (_) { /* Storage is optional, including on private browser tabs. */ }
    }
    async chunk(part, group) {
      return this.limited(async () => {
        if (this.cancelled || group.cancelled) throw new Error("下载已取消");
        const cache = await this.cache;
        if (cache && !this.cacheBroken) {
          try {
            const saved = await this.deadline(cache.match(part.path));
            if (saved) {
              const bytes = new Uint8Array(await this.deadline(saved.arrayBuffer()));
              if (bytes.length === part.bytes) { this.stats.cacheHits++; this.track(part, bytes.length, true); return bytes; }
              await this.deadline(cache.delete(part.path));
            }
          } catch (_) { this.cacheBroken = true; this.stats.cacheFailures++; }
        }
        for (let attempt = 0; attempt < 3; attempt++) {
          if (group.cancelled) throw new Error("下载已取消");
          const abort = typeof AbortController === "function" ? new AbortController() : null;
          let timeout, reader, rejectStalled;
          const stalled = new Promise((_, reject) => { rejectStalled = reject; });
          const stop = () => { abort?.abort(); reader?.cancel().catch(() => {}); rejectStalled(new Error("下载已取消")); };
          group.stops.add(stop);
          const heartbeat = () => {
            clearTimeout(timeout);
            timeout = setTimeout(() => { abort?.abort(); rejectStalled(new Error("资源连接暂时没有响应")); }, 20000);
          };
          try {
            heartbeat();
            this.stats.requests++;
            if (attempt) { this.stats.retries++; globalThis.toyroomStartup?.({phase:'retry',file:part.path,attempt}); }
            const options = abort ? {signal:abort.signal} : {};
            if (attempt) options.cache = 'reload';
            const response = await Promise.race([this.fetch(part.path, options), stalled]);
            if (!response.ok) throw new Error(`资源请求失败 (${response.status})`);
            // Preallocate one small part, avoiding Response.arrayBuffer's extra whole-part copy.
            let bytes;
            if (response.body?.getReader) {
              bytes = new Uint8Array(part.bytes);
              reader = response.body.getReader();
              let offset = 0;
              while (true) {
                const { value, done } = await Promise.race([reader.read(), stalled]);
                if (done) break;
                if (offset + value.length > bytes.length) throw new Error("下载资源长度错误");
                bytes.set(value, offset); offset += value.length;
                heartbeat(); this.track(part, offset);
              }
              if (offset !== part.bytes) throw new Error("下载资源不完整");
            } else {
              bytes = new Uint8Array(await Promise.race([response.arrayBuffer(), stalled]));
              if (bytes.length !== part.bytes) throw new Error("下载资源不完整");
            }
            clearTimeout(timeout);
            this.track(part, bytes.length);
            this.save(cache, part, bytes);
            return bytes;
          } catch (error) {
            abort?.abort(); reader?.cancel().catch(() => {});
            if (group.cancelled) throw error;
            if (attempt === 2) { error.toyroomStage='download'; error.toyroomPart=part.path; throw error; }
            await new Promise(resolve => setTimeout(resolve, 350 * (attempt + 1)));
          } finally { clearTimeout(timeout); group.stops.delete(stop); }
        }
      });
    }
    compressedStream(asset) {
      const pending = new Map();
      const group = { cancelled: false, stops: new Set() };
      let index = 0, bytes = null, offset = 0, cancelled = false;
      const cancel = () => {
        cancelled = true; group.cancelled = true; bytes = null; pending.clear();
        for (const stop of group.stops) stop();
        this.groups.delete(group);
      };
      group.cancel = cancel; this.groups.add(group);
      const prefetch = () => {
        for (let i = index; i < Math.min(index + 3, asset.parts.length); i++) {
          if (!pending.has(i)) {
            // Catch immediately, including errors in a prefetched future part.
            pending.set(i, this.chunk(asset.parts[i], group).then(data => ({ data }), error => ({ error })));
          }
        }
      };
      return new ReadableStream({
        pull: async controller => {
          try {
            if (cancelled) return;
            if (!bytes) {
              if (index >= asset.parts.length) { this.groups.delete(group); controller.close(); return; }
              prefetch();
              const result = await pending.get(index);
              if (cancelled) return;
              if (result.error) throw result.error;
              bytes = result.data; offset = 0;
            }
            const end = Math.min(offset + 65536, bytes.length);
            controller.enqueue(bytes.subarray(offset, end)); offset = end;
            if (offset === bytes.length) { pending.delete(index++); bytes = null; prefetch(); }
          } catch (error) { cancel(); controller.error(error); }
        },
        cancel,
      });
    }
    async portable(compressed, file) {
      let worker = null;
      // Older Android browser engines may lack DecompressionStream. Keep gzip
      // off their UI thread, and acknowledge every input to enforce backpressure.
      if (typeof Worker === 'function') {
        try {
          worker = new Worker('gzip-worker.js');
          await new Promise((resolve,reject) => {
            const timer = setTimeout(() => reject(new Error('Decoder worker unavailable')),3000);
            worker.onmessage = e => { clearTimeout(timer); e.data.ready ? resolve() : reject(new Error(e.data.error)); };
            worker.onerror = e => {clearTimeout(timer); reject(new Error(e.message || 'Decoder worker unavailable'));};
            worker.postMessage({init:true});
          });
        } catch (_) { worker?.terminate(); worker = null; }
      }
      this.stats.decoders[file] = worker ? 'worker' : 'portable';
      if (!worker && !globalThis.fflate?.Gunzip) throw new Error('解压组件没有加载，请重试');
      const reader = compressed.getReader();
      let decoder, ended=false, produced=false, rejectPending, lastYield=performance.now();
      return new ReadableStream({
        start(controller) {
          if (!worker) decoder = new fflate.Gunzip((data,final) => {
            if (data.length) {produced=true; controller.enqueue(data);}
            if (final) controller.close();
          });
        },
        async pull(controller) {
          if (ended) return;
          try {
            produced=false;
            do {
              const {value,done} = await reader.read(); ended=done;
              if (worker) {
                const input = value ? value.slice() : new Uint8Array(0);
                const output = await new Promise((resolve,reject) => {
                  rejectPending=reject;
                  worker.onmessage=e => e.data.error ? reject(new Error(e.data.error)) : resolve(e.data);
                  worker.onerror=e => reject(new Error(e.message || '解压失败'));
                  worker.postMessage({input,final:done},[input.buffer]);
                });
                rejectPending=null;
                for (const data of output.chunks) {if (data.length) {produced=true;controller.enqueue(data);}}
                if (done) {worker.terminate();worker=null;controller.close();}
              } else {
                decoder.push(value || new Uint8Array(0),done);
                if (performance.now()-lastYield > 8) {await new Promise(r=>setTimeout(r,0));lastYield=performance.now();}
              }
            } while (!produced && !ended);
          } catch (error) {ended=true;worker?.terminate();controller.error(error);reader.cancel().catch(()=>{});}
        },
        cancel(reason) {ended=true;rejectPending?.(new Error('下载已取消'));worker?.terminate();return reader.cancel(reason);},
      });
    }
    async response(file) {
      const asset = this.manifest[file];
      if (!asset) return this.fetch(file);
      const compressed = this.compressedStream(asset);
      let unpacked;
      try {
        if (typeof DecompressionStream !== "function") throw new Error("Use portable decompressor");
        unpacked = compressed.pipeThrough(new DecompressionStream("gzip"));
        this.stats.decoders[file]='native';
      } catch (_) {
        unpacked = await this.portable(compressed,file);
      }
      return new Response(unpacked, { headers: { "Content-Type": asset.type, "Content-Length": String(asset.originalBytes), 'X-Toyroom-Asset':file } });
    }
  }
  // Avoid building a second 400+ MB copy inside the browser's response accumulator.
  async function toyroomReadBuffer(response, expected) {
    const size = Number(expected || response.headers.get("Content-Length"));
    if (!size || !response.body?.getReader) return response.arrayBuffer();
    const reader = response.body.getReader();
    let offset = 0, bytes, lastProgress=0;
    try {
      bytes = new Uint8Array(size);
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        if (offset + value.length > size) throw new Error("解压资源长度错误");
        bytes.set(value, offset); offset += value.length;
        if (performance.now()-lastProgress>150) {
          globalThis.toyroomStartup?.({phase:'decode',file:response.headers.get('X-Toyroom-Asset'),bytes:offset,total:size});
          lastProgress=performance.now();
        }
      }
      if (offset !== size) throw new Error("解压资源不完整");
      return bytes.buffer;
    } catch (error) { reader.cancel().catch(() => {}); throw error; }
  }
  globalThis.ToyroomAssets = ToyroomAssets;
  globalThis.toyroomReadBuffer = toyroomReadBuffer;
})();
