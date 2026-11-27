(() => {
  let foreground = false;
  let pageOpen = true;
  let stop = () => {};
  let willowJingle;

  const audio = {
    get canPlay() {
      return foreground && pageOpen && !document.hidden;
    },
    setForeground(value) {
      foreground = value === true;
      stopIfBackground();
      if (foreground && willowJingle?.pending) willowJingle.play();
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

  // Load the selected YouTube video when Willow opens. The Conch view does
  // not contact the player until then.
  willowJingle = {
    panel: null,
    frame: null,
    pending: false,
    play() {
      this.pending = true;
      if (!audio.canPlay) return;
      this.pending = false;
      this.ensure();
      this.panel.hidden = false;
      if (!this.frame.src) {
        this.frame.src =
          "https://www.youtube.com/embed/f5v2xcBNNic?autoplay=1&playsinline=1&rel=0";
      }
    },
    stop() {
      this.pending = false;
      // Remove the document so playback stops even if navigation is blocked.
      this.panel?.remove();
      this.panel = null;
      this.frame = null;
    },
    ensure() {
      if (this.frame) return;
      const panel = document.createElement("section");
      panel.className = "willow-jingle";
      panel.hidden = true;
      panel.innerHTML = [
        '<div class="willow-jingle-heading"><p>♪ One Wish Willow Jingle</p><button type="button" aria-label="윌로우 음악 닫기">닫기</button></div>',
        '<iframe title="One Wish Willow Jingle (official YouTube player)" allow="autoplay; encrypted-media; picture-in-picture" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>',
        '<a href="https://www.youtube.com/watch?v=f5v2xcBNNic">YouTube에서 열기</a>',
      ].join("");
      document.body.append(panel);
      this.panel = panel;
      this.frame = panel.querySelector("iframe");
      panel.querySelector("button").addEventListener("click", () => this.stop());
      panel.querySelector("a").addEventListener("click", (event) => {
        const bridge = window.chrome?.webview;
        if (!bridge) return;
        event.preventDefault();
        bridge.postMessage({ type: "openWillowJingle" });
      });
    },
  };
  window.__memeConchWillow = willowJingle;
})();
