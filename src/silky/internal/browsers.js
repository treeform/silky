function installSilkyBrowserInputs(canvas, receiveRune, receiveModifiers) {
  // The Emscripten window uses one canvas for its lifetime.
  if (canvas.silkyInputListeners) {
    canvas.silkyInputListeners.abort();
  }
  const controller = new AbortController();
  canvas.silkyInputListeners = controller;
  const options = {capture: true, signal: controller.signal};
  let fallbackKey = null;

  function beforeKeyboard(event) {
    if (event.target !== canvas) {
      return;
    }
    if (event.type === 'keydown' || event.type === 'keyup') {
      fallbackKey = null;
    }
    if (event.type === 'keypress' && fallbackKey === event.key) {
      // Some synthetic event sources send keypress even after cancellation.
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    receiveModifiers(16 | (event.ctrlKey ? 1 : 0) |
      (event.shiftKey ? 2 : 0) | (event.altKey ? 4 : 0) |
      (event.metaKey ? 8 : 0) |
      (event.getModifierState('AltGraph') ? 32 : 0));
  }

  function afterKeyboard(event) {
    if (event.target === canvas) {
      receiveModifiers(0);
    }
  }

  for (const type of ['keydown', 'keyup', 'keypress']) {
    // Document capture runs before Windy's canvas callbacks.
    document.addEventListener(type, beforeKeyboard, options);
    document.addEventListener(type, afterKeyboard, {
      signal: controller.signal
    });
  }

  canvas.addEventListener('keydown', function(event) {
    // Windy cancels keydown, suppressing the keypress that supplies its runes.
    if (!event.defaultPrevented || event.isComposing || event.metaKey ||
        (event.ctrlKey && !event.getModifierState('AltGraph'))) {
      return;
    }
    const characters = Array.from(event.key);
    if (characters.length === 1 &&
        receiveRune(characters[0].codePointAt(0))) {
      fallbackKey = event.key;
    }
  }, options);
}
