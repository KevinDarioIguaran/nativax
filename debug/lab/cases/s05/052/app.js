// NativaX Lab · clock, theme, counter and ripple. Everything real, nothing simulated.
window.__nativaxCase = 'color.052';
(function () {
  var clock = document.getElementById('clock');
  function pad(n) { return n < 10 ? '0' + n : String(n); }
  function tick() {
    var d = new Date();
    if (clock) clock.textContent = pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
  }
  tick();
  setInterval(tick, 1000);

  var pings = 0;
  var badge = document.getElementById('pings');
  window.__nativaxPings = 0;
  var ping = document.getElementById('ping');
  if (ping) {
    ping.addEventListener('click', function (ev) {
      pings++;
      window.__nativaxPings = pings;
      if (badge) badge.textContent = String(pings);
      var host = ping.parentNode;
      if (host) {
        var r = document.createElement('span');
        r.className = 'ripple';
        host.appendChild(r);
      }
    });
  }

  var toggle = document.getElementById('theme-toggle');
  if (toggle) {
    toggle.addEventListener('click', function () {
      document.body.classList.toggle('light');
      toggle.textContent = document.body.classList.contains('light') ? 'Dark' : 'Theme';
    });
  }

  var cards = document.querySelectorAll('.card');
  for (var i = 0; i < cards.length; i++) {
    cards[i].addEventListener('click', function () { this.classList.toggle('is-selected'); });
  }
})();
