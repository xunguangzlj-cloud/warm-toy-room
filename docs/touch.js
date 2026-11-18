(() => {
  const $ = selector => document.querySelector(selector);
  const canvas = $("#game"), hud = $("#touch-hud"), stick = $("#touch-stick"), tip = $("#touch-tip");
  const editor = $("#touch-editor"), sizeSlider = $("#touch-size"), sizeValue = $("#touch-size-value");
  const controls = [...document.querySelectorAll("[data-layout]")];
  const buttons = [...hud.querySelectorAll("[data-touch-key]")];
  const buttonPointers = new Map(), layoutKey = "toyroom-touch-layout-v1";
  const names = { stick: "移动摇杆", jump: "跳跃", roll: "翻滚", context: "互动 / 拿放", throw: "投掷", swap: "换人", companion: "同伴", pause: "暂停", lighting: "光线", settings: "按键设置", fullscreen: "全屏" };
  let moving = null, looking = null, paused = false, editing = false, activated = false, drag = null;
  let layouts = {}, snapshot, selected = "stick", editorGuardUntil = 0;
  try { layouts = JSON.parse(localStorage.getItem(layoutKey) || "{}"); } catch (_) { /* Default layout. */ }
  if (!layouts || typeof layouts !== "object" || Array.isArray(layouts)) layouts = {};
  const send = (...args) => window.toyroomTouchInput?.(...args);
  const clamp = (n, a, b) => Math.min(b, Math.max(a, n));
  const bounds = () => hud.getBoundingClientRect();
  const orientation = () => bounds().width >= bounds().height ? "landscape" : "portrait";
  const safe = () => {
    const css = getComputedStyle(hud);
    return { left: Math.max(8, parseFloat(css.paddingLeft) || 0), right: Math.max(8, parseFloat(css.paddingRight) || 0),
      top: Math.max(8, parseFloat(css.paddingTop) || 0), bottom: Math.max(8, parseFloat(css.paddingBottom) || 0) };
  };
  function defaults() {
    const { width: w, height: h } = bounds(), unit = Math.min(w, h), inset = safe();
    const b = clamp(unit * .16, 48, 72), menu = clamp(unit * .115, 40, 52);
    // Exactly 1.5 times the previous default joystick diameter.
    const j = clamp(unit * .17, 80, 128) * 1.5;
    const left = inset.left, right = w - inset.right, top = inset.top, bottom = h - inset.bottom;
    const values = {
      stick: [left + j / 2 + 8, bottom - j / 2 - 8, j],
      context: [right - b * 1.7, bottom - b * .55, b], throw: [right - b * .55, bottom - b * .55, b],
      roll: [right - b * 1.7, bottom - b * 1.7, b], jump: [right - b * .55, bottom - b * 1.7, b],
      swap: [left + menu / 2, h * .42, menu], companion: [left + menu * 1.7, h * .42, menu],
      pause: [left + menu / 2, h * .42 + menu * 1.2, menu],
      lighting: [right - menu * 2.9, top + menu / 2, menu], settings: [right - menu * 1.7, top + menu / 2, menu],
      fullscreen: [right - menu * .5, top + menu / 2, menu],
    };
    return Object.fromEntries(Object.entries(values).map(([id, [x, y, base]]) => [id, { x: x / w, y: y / h, base, scale: 1 }]));
  }
  function geometry(id) {
    const d = defaults()[id], saved = layouts[orientation()]?.[id];
    return { ...d, x: Number.isFinite(saved?.x) ? clamp(saved.x, 0, 1) : d.x,
      y: Number.isFinite(saved?.y) ? clamp(saved.y, 0, 1) : d.y,
      scale: Number.isFinite(saved?.scale) ? clamp(saved.scale, .65, 1.65) : 1 };
  }
  function put(id, values) {
    const mode = orientation();
    if (!layouts[mode] || typeof layouts[mode] !== "object") layouts[mode] = {};
    const current = geometry(id);
    layouts[mode][id] = { x: current.x, y: current.y, scale: current.scale, ...values };
  }
  function layout() {
    if (!activated) return;
    const { width: w, height: h } = bounds(), inset = safe();
    for (const control of controls) {
      const id = control.dataset.layout, g = geometry(id);
      const size = Math.min(g.base * g.scale, w - inset.left - inset.right, h - inset.top - inset.bottom);
      const x = clamp(g.x * w, inset.left + size / 2, w - inset.right - size / 2);
      const y = clamp(g.y * h, inset.top + size / 2, h - inset.bottom - size / 2);
      Object.assign(control.style, { left: `${x}px`, top: `${y}px`, width: `${size}px`, height: `${size}px`,
        fontSize: `${clamp(size * .23, 10, 19)}px` });
      control.toggleAttribute("data-selected", editing && selected === id);
    }
    if (editing) {
      $("#touch-selected").textContent = names[selected];
      sizeSlider.value = Math.round(geometry(selected).scale * 100);
      sizeValue.textContent = `${sizeSlider.value}%`;
    }
  }
  function clearStick() {
    moving = null; stick.style.setProperty("--stick-x", "0px"); stick.style.setProperty("--stick-y", "0px");
    send("move", 0, 0);
  }
  function buttonAction(button, pressed) {
    const action = button.dataset.touchKey;
    if (action === "throw") send("throw", pressed);
    else if (action === "context") { if (pressed) send("context"); }
    else send("key", action, pressed);
  }
  function clear() {
    clearStick(); looking = null; drag = null;
    for (const button of buttonPointers.values()) { button.removeAttribute("data-held"); buttonAction(button, false); }
    buttonPointers.clear(); send("reset");
  }
  function updateStick(event) {
    const b = stick.getBoundingClientRect(), radius = b.width * .37;
    const x = (event.clientX - b.left - b.width / 2) / radius, y = (event.clientY - b.top - b.height / 2) / radius;
    const length = Math.max(1, Math.hypot(x, y));
    stick.style.setProperty("--stick-x", `${x / length * radius}px`);
    stick.style.setProperty("--stick-y", `${y / length * radius}px`);
    send("move", x / length, y / length);
  }
  function beginEdit() {
    if (paused || editing) return;
    clear(); snapshot = JSON.stringify(layouts); editing = true; editor.hidden = false;
    hud.setAttribute("data-editing", ""); document.body.setAttribute("data-editing-controls", "");
    $("#touch-save-status").textContent = "横屏、竖屏的布局分别保存";
    send("layout", true); layout();
  }
  function endEdit(save) {
    if (!editing) return;
    if (save) {
      try { localStorage.setItem(layoutKey, JSON.stringify(layouts)); }
      catch (_) { $("#screen-notice").textContent = "浏览器禁止保存，本次布局仍然可用。"; $("#screen-notice").hidden = false; }
    } else layouts = JSON.parse(snapshot);
    clear(); editing = false; editor.hidden = true; editorGuardUntil = Date.now() + 250;
    hud.removeAttribute("data-editing"); document.body.removeAttribute("data-editing-controls");
    paused = false; hud.removeAttribute("data-paused"); send("layout", false); layout();
  }
  window.toyroomTouchPause = value => {
    paused = value; hud.toggleAttribute("data-paused", paused);
    if (paused) queueMicrotask(clear);
  };
  window.toyroomTouchResize = () => { clear(); layout(); };
  window.activateToyroomTouch = () => {
    if (activated) return;
    activated = true; hud.hidden = false; layout();
    // Each pointer owns exactly one control; releasing jump never releases the stick.
    for (const control of controls) {
      control.addEventListener("pointerdown", event => {
        if (!editing) return;
        event.preventDefault(); event.stopImmediatePropagation(); selected = control.dataset.layout;
        const b = control.getBoundingClientRect();
        drag = { id: event.pointerId, control, dx: event.clientX - b.left - b.width / 2, dy: event.clientY - b.top - b.height / 2 };
        control.setPointerCapture(event.pointerId); layout();
      }, true);
      control.addEventListener("pointermove", event => {
        if (!editing || drag?.id !== event.pointerId || drag.control !== control) return;
        const b = bounds(); put(selected, { x: (event.clientX - b.left - drag.dx) / b.width, y: (event.clientY - b.top - drag.dy) / b.height }); layout();
        event.preventDefault(); event.stopImmediatePropagation();
      }, true);
      for (const type of ["pointerup", "pointercancel", "lostpointercapture"]) control.addEventListener(type, event => {
        if (!editing) return;
        if (drag?.id === event.pointerId) drag = null;
        event.stopImmediatePropagation();
      }, true);
      control.addEventListener("click", event => {
        if (editing || Date.now() < editorGuardUntil) { event.preventDefault(); event.stopImmediatePropagation(); }
      }, true);
    }
    stick.addEventListener("pointerdown", event => {
      if (paused || editing || moving !== null) return;
      event.preventDefault(); moving = event.pointerId; stick.setPointerCapture(moving); updateStick(event);
    });
    stick.addEventListener("pointermove", event => { if (event.pointerId === moving) updateStick(event); });
    for (const type of ["pointerup", "pointercancel", "lostpointercapture"]) stick.addEventListener(type, event => {
      if (event.pointerId === moving) clearStick();
    });
    canvas.addEventListener("pointerdown", event => {
      if (paused || editing || looking || event.button !== 0) return;
      event.preventDefault(); looking = { id: event.pointerId, x: event.clientX, y: event.clientY };
      canvas.setPointerCapture(event.pointerId);
    });
    canvas.addEventListener("pointermove", event => {
      if (event.pointerId !== looking?.id) return;
      const x = event.clientX - looking.x, y = event.clientY - looking.y;
      looking.x = event.clientX; looking.y = event.clientY;
      if (x || y) { tip.hidden = true; send("look", x * 2, y * 2); }
    });
    for (const type of ["pointerup", "pointercancel", "lostpointercapture"]) canvas.addEventListener(type, event => {
      if (event.pointerId === looking?.id) looking = null;
    });
    for (const button of buttons) {
      const menu = button.closest(".touch-menu");
      button.addEventListener("pointerdown", event => {
        if (editing || (paused && !menu) || event.button !== 0 || button.hasAttribute("data-held")) return;
        event.preventDefault(); button.setPointerCapture(event.pointerId); buttonPointers.set(event.pointerId, button);
        button.setAttribute("data-held", ""); buttonAction(button, true);
      });
      for (const type of ["pointerup", "pointercancel", "lostpointercapture"]) button.addEventListener(type, event => {
        if (buttonPointers.get(event.pointerId) !== button) return;
        buttonPointers.delete(event.pointerId); button.removeAttribute("data-held"); buttonAction(button, false);
      });
    }
    $("#touch-settings").onclick = beginEdit;
    sizeSlider.oninput = () => { put(selected, { scale: Number(sizeSlider.value) / 100 }); layout(); };
    $("#touch-save").onclick = () => endEdit(true); $("#touch-cancel").onclick = () => endEdit(false);
    $("#touch-reset").onclick = () => { layouts[orientation()] = {}; layout(); };
    window.addEventListener("keydown", event => {
      if (editing && event.key === "Escape") { event.preventDefault(); event.stopImmediatePropagation(); endEdit(false); }
    }, true);
    window.addEventListener("blur", clear);
    document.addEventListener("visibilitychange", () => { if (document.hidden) clear(); });
  };
})();
