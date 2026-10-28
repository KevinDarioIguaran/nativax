var clicks = 0;
var count = document.getElementById('count');
var title = document.getElementById('title');
var card = document.getElementById('card');
var toggle = document.getElementById('toggle');

count.addEventListener('click', function () {
  clicks++;
  count.textContent = 'Clicked ' + clicks + ' times';
  title.textContent = clicks % 2 ? 'DOM updated by script' : 'HTML + CSS + JavaScript';
  count.style.backgroundColor = clicks % 2 ? '#e94560' : '#0f3460';
});

var dark = false;
toggle.addEventListener('click', function () {
  dark = !dark;
  if (dark) card.classList.add('theme-dark');
  else card.classList.remove('theme-dark');
  toggle.textContent = dark ? 'Light theme' : 'Toggle theme';
});

console.log('app.js ready: nodes ' + document.querySelectorAll('div').length);

