(() => {
  let foreground = false;
  let pageOpen = true;
  let stop = () => {};

  const audio = {
    get canPlay() {
      return foreground && pageOpen && !document.hidden;
    },
    setForeground(value) {
      foreground = value === true;
      stopIfBackground();
    },
    setStopHandler(handler) {
      stop = handler;
      stopIfBackground();
    },
  };

  function stopIfBackground() {
    if (!audio.canPlay) stop();
  }

  document.addEventListener("visibilitychange", stopIfBackground);
  window.addEventListener("pagehide", () => {
    pageOpen = false;
    stopIfBackground();
  });
  window.addEventListener("pageshow", () => {
    pageOpen = true;
  });
  window.__memeConchAudio = audio;
})();
