(() => {
  const $ = selector => document.querySelector(selector);
  const canvas = $("#game"), intro = $("#intro"), status = $("#status"), progress = $("#progress");
  const actions = $(".actions"), play = $("#play"), mobile = $("#mobile"), look = $("#look");
  const fullscreen = $("#fullscreen"), screenNotice = $("#screen-notice");
  const errorDetails = $('#load-details'), errorText = $('#load-error');
  const resources = globalThis.TOYROOM_PAYLOAD;
  let ready = false, starting = false, hasLocked = false, failed = false, mobileMode = false, renderHeight = 720;
  let resizeFrame, noticeTimer, lastProgress = 0;
  let startupStage = 'download';
  const stageNames = {download:'下载资源',retry:'重试资源',decode:'解压资源',compile:'准备游戏引擎',storage:'读取游戏设置',mount:'装载游戏资源',scene:'准备房间'};
  const diagnostics = {events:[],engineErrors:[]};
  const record = event => {diagnostics.events.push({time:Math.round(performance.now()),...event});if(diagnostics.events.length>16)diagnostics.events.shift();};
  const mib = bytes => (bytes / 1048576).toFixed(1);
  const standalone = () => !!navigator.standalone || window.matchMedia?.("(display-mode: standalone)").matches;
  const fullscreenElement = () => document.fullscreenElement || document.webkitFullscreenElement;
  function notice(message) {
    clearTimeout(noticeTimer); screenNotice.textContent = message; screenNotice.hidden = false;
    noticeTimer = setTimeout(() => { screenNotice.hidden = true; }, 9000);
  }
  function screenSize() {
    const width = Math.max(1, document.documentElement.clientWidth || innerWidth);
    const height = Math.max(1, window.visualViewport?.height || innerHeight);
    const aspect = width / height;
    return { width: Math.max(2, Math.round(renderHeight * aspect / 2) * 2),
      height: renderHeight, cssHeight: height };
  }
  function resize() {
    cancelAnimationFrame(resizeFrame);
    resizeFrame = requestAnimationFrame(() => {
      const size = screenSize();
      document.documentElement.style.setProperty("--screen-height", `${size.cssHeight}px`);
      if (canvas.width !== size.width) canvas.width = size.width;
      if (canvas.height !== size.height) canvas.height = size.height;
      window.toyroomTouchResize?.();
    });
  }
  window.setToyroomRenderHeight = height => {
    if (![540, 720, 1080].includes(height)) return;
    renderHeight = height; resize();
  };
  const updateFullscreen = () => {
    fullscreen.textContent = fullscreenElement() ? "退出全屏" : standalone() ? "已全屏" : "全屏";
    fullscreen.setAttribute("aria-label", fullscreen.textContent); resize();
  };
  window.toyroomFullscreen = async (enterOnly = false) => {
    try {
      if (fullscreenElement()) {
        if (!enterOnly) await (document.exitFullscreen?.() || document.webkitExitFullscreen?.());
      } else if (!standalone()) {
        const root = document.documentElement;
        if (root.requestFullscreen) await root.requestFullscreen({ navigationUI: "hide" });
        else if (root.webkitRequestFullscreen) await root.webkitRequestFullscreen();
        else throw new Error("Fullscreen unavailable");
      }
      if (mobileMode && (fullscreenElement() || standalone())) {
        try { await screen.orientation?.lock?.("landscape"); } catch (_) { /* Rotation is optional. */ }
      }
    } catch (_) {
      notice(/iPhone|iPad|iPod/.test(navigator.userAgent) ? "此浏览器限制网页全屏：在 Safari 分享菜单中添加到主屏幕，再从图标打开。" : "浏览器未允许全屏。可在浏览器菜单开启全屏，或添加到主屏幕后打开。画面已铺满可用区域。");
    }
    updateFullscreen(); canvas.focus({ preventScroll: true });
  };
  fullscreen.onclick = () => window.toyroomFullscreen();
  for (const event of ["fullscreenchange", "webkitfullscreenchange"]) document.addEventListener(event, updateFullscreen);
  window.addEventListener("resize", resize);
  window.visualViewport?.addEventListener("resize", resize);
  window.addEventListener("orientationchange", () => setTimeout(resize, 150));
  document.addEventListener("pointerlockchange", () => {
    if (document.pointerLockElement === canvas) hasLocked = true;
    look.hidden = !ready || hasLocked || mobileMode;
  });
  function showError(error) {
    if (failed) return;
    failed = true; console.error(error); progress.hidden = true;
    assets.cancel();
    const message = String(error?.message || error);
    // A wasm out-of-bounds trap or arbitrary RangeError is not evidence that
    // the user's device has insufficient RAM. Preserve the real failure.
    const memory = /out of memory|not enough memory|allocation failed|failed to allocate|array buffer allocation failed/i.test(message);
    status.textContent = memory
      ? "游戏启动时申请内存失败。可关闭其他游戏标签页后重试，已缓存资源会继续使用。"
      : `${stageNames[error?.toyroomStage || startupStage] || '启动'}未完成：${message.slice(0, 110)}。重试会使用已缓存资源。`;
    errorDetails.hidden=false;
    errorText.textContent=JSON.stringify({stage:error?.toyroomStage || startupStage,name:error?.name,message,
      resource:error?.toyroomPart || null,transport:assets.stats,events:diagnostics.events,
      engine:diagnostics.engineErrors,browser:navigator.userAgent},null,2);
    play.textContent = "重试载入"; play.onclick = () => location.reload();
    mobile.hidden = true; actions.hidden = false;
  }
  const assets = new ToyroomAssets(resources, ({ loaded, total, cached }) => {
    if (failed) return;
    progress.value = loaded / total * 100;
    if (Date.now() - lastProgress < 100 && loaded < total) return;
    lastProgress = Date.now();
    status.textContent = loaded >= total ? "下载完成，正在解压并准备房间…"
      : `${cached ? "读取已缓存资源" : "下载游戏资源"} · ${mib(loaded)} / ${mib(total)} MiB`;
    startupStage=loaded>=total?'decode':'download';
  });
  window.toyroomAssetFetch = file => assets.response(file);
  window.toyroomFatal = showError;
  window.toyroomStartup = event => {
    if (ready || failed) return;
    startupStage=event.phase;
    if (event.phase==='decode') {
      if (assets.loaded.size && [...assets.loaded.values()].reduce((a,b)=>a+b,0) < assets.total) return;
      status.textContent=`解压游戏资源 · ${Math.min(100,Math.round(event.bytes/event.total*100))}%`;
    } else {
      record(event);
      const suffix=event.phase==='retry'?' · 已保存的部分无需重下':'';
      status.textContent=`${stageNames[event.phase] || '准备游戏'}…${suffix}`;
    }
  };
  window.addEventListener('unhandledrejection', event => {
    if (starting && !ready && !failed) showError(event.reason);
  });
  function setReady() {
    if (ready || failed) return;
    ready = true; resize(); intro.hidden = true; look.hidden = hasLocked || mobileMode;
    if (mobileMode) window.activateToyroomTouch();
    canvas.focus({ preventScroll: true }); assets.prune();
  }
  async function start(touch) {
    if (starting) return;
    starting = true; mobileMode = touch;
    document.body.toggleAttribute("data-mobile", touch);
    // Request in the tap handler, before awaiting downloads, to preserve user activation.
    if (touch) window.toyroomFullscreen(true);
    actions.hidden = true; progress.hidden = false; status.textContent = "正在连接游戏资源…";
    if (navigator.storage?.persist) navigator.storage.persist().catch(() => {});
    const size = screenSize(); canvas.width = size.width; canvas.height = size.height; resize();
    const args = ["--resolution", `${size.width}x${size.height}`];
    if (touch) args.push("--", "--web-mobile");
    const engine = new Engine({ executable: "index", mainPack: "index.pck", canvas,
      canvasResizePolicy: 0, focusCanvas: true, args,
      fileSizes: Object.fromEntries(Object.entries(resources).map(([file, a]) => [file, a.originalBytes])),
      onPrint(message) { console.info(message); if (message.startsWith("ROOM_READY")) setTimeout(setReady, 0); },
      onPrintError(message) { console.error(message);diagnostics.engineErrors.push(String(message));if(diagnostics.engineErrors.length>6)diagnostics.engineErrors.shift(); },
    });
    try {
      // Initialize the small engine first: don't hold the 407 MiB pack while
      // compiling wasm or while waiting for browser storage permissions.
      await engine.init('index');
      if(failed)return;
      window.toyroomStartup({phase:'download'});
      await engine.preloadFile('index.pck','index.pck');
      if(failed)return;
      status.textContent='资源已就绪，正在进入房间…';
      await new Promise(resolve=>requestAnimationFrame(()=>setTimeout(resolve,0)));
      await engine.start({args:['--main-pack','index.pck',...args]});
    } catch (error) { showError(error); }
  }
  canvas.addEventListener("webglcontextlost", event => {
    event.preventDefault();
    showError(new Error("浏览器中断了图形显示，请关闭其他游戏标签页后重试")); intro.hidden = false;
  });
  const missing = typeof Engine === "function" ? Engine.getMissingFeatures({ threads: false }) : ["游戏引擎文件未下载成功"];
  if (missing.length) {
    status.textContent = `此浏览器尚不能启动游戏：${missing.join("；")}。请在更新后的系统浏览器中打开。`;
    actions.hidden = true;
  } else {
    status.textContent = `首次载入约 ${mib(assets.total)} MiB · 已下载资源会保存在本机`;
    assets.allCached().then(saved => {
      if (saved && !starting) status.textContent = "游戏已保存在本机 · 本次无需重新下载整包";
    });
    play.onclick = () => start(false); mobile.onclick = () => start(true);
  }
  updateFullscreen();
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(() => {});
})();
