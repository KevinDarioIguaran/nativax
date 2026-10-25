/// Built-in performance scenarios and the external benchmark registry.
library;

import 'dart:math' as math;

import 'externals.dart';

enum ScenarioKind { dom, scroll, js, idle, external }

class ScenarioOp {
  const ScenarioOp(this.name, this.js, {this.scroll = false});
  final String name;
  final String js;
  final bool scroll;
}

class PerfScenario {
  const PerfScenario({
    required this.id,
    required this.title,
    required this.kind,
    required this.source,
    required this.description,
    this.pageBuilder,
    this.externalId,
    this.setupJs = '',
    this.setupWaitJs,
    this.ops = const [],
    this.startJs,
    this.waitJs,
    this.readJs,
    this.idleMs = 0,
    this.timeoutMs = 30000,
    this.expectedNodes,
    this.notes = const [],
  });

  final String id;
  final String title;
  final ScenarioKind kind;

  /// Original benchmark or specification this scenario models.
  final String source;
  final String description;
  final String Function()? pageBuilder;
  final String? externalId;
  final String setupJs;
  final String? setupWaitJs;
  final List<ScenarioOp> ops;
  final String? startJs;
  final String? waitJs;
  final String? readJs;
  final int idleMs;
  final int timeoutMs;
  final int? expectedNodes;
  final List<String> notes;

  bool get isExternal => externalId != null;
}

String rowsPage({int initialRows = 0, bool twoD = false, int tiles = 900}) {
  if (twoD) {
    final side = math.sqrt(tiles).ceil();
    return '''<!doctype html><html><head><meta charset="utf-8">
<style>
html,body{margin:0;padding:0;background:#0b0f14}
#board{position:relative;width:${side * 200}px;height:${side * 200}px}
.tile{position:absolute;width:200px;height:200px;border-radius:12px}
</style></head><body><div id="board"></div><script>
(function(){
  var board=document.getElementById('board');
  var frag=document.createDocumentFragment();
  for(var y=0;y<$side;y++){
    for(var x=0;x<$side;x++){
      var d=document.createElement('div');
      d.className='tile';
      d.style.left=(x*200)+'px';
      d.style.top=(y*200)+'px';
      var a=(x*13+y*7)%360;
      d.style.background='linear-gradient(135deg, hsl('+a+',70%,55%), hsl('+((a+80)%360)+',70%,35%))';
      frag.appendChild(d);
    }
  }
  board.appendChild(frag);
  window.__perf={tiles:$side*$side};
})();
</script></body></html>''';
  }
  return '''<!doctype html><html><head><meta charset="utf-8">
<style>
html,body{margin:0;padding:0;font:14px sans-serif;background:#fff}
#rows{padding:0;margin:0}
.row{height:32px;line-height:32px;padding:0 12px;border-bottom:1px solid #ddd}
.row:nth-child(even){background:#f6f7fb}
</style></head><body><div id="rows"></div><script>
(function(){
  var rows=document.getElementById('rows');
  var count=0;
  window.__perf={
    get count(){return count;},
    create:function(n){
      var frag=document.createDocumentFragment();
      for(var i=0;i<n;i++){
        var d=document.createElement('div');
        d.className='row';
        d.textContent='Row '+(count+i)+' · alpha beta gamma delta';
        frag.appendChild(d);
      }
      rows.appendChild(frag);
      count+=n;
      document.body.getBoundingClientRect();
      return count;
    },
    updateEvery:function(step){
      var list=rows.children;
      for(var i=0;i<list.length;i+=step){
        list[i].textContent='Updated '+(i/step);
      }
      document.body.getBoundingClientRect();
      return list.length;
    },
    removeAll:function(){
      var n=rows.children.length;
      rows.textContent='';
      count=0;
      document.body.getBoundingClientRect();
      return n;
    }
  };
  if ($initialRows > 0) window.__perf.create($initialRows);
})();
</script></body></html>''';
}

String jsPage() => '''<!doctype html><html><head><meta charset="utf-8">
<style>body{margin:0;font:14px monospace;background:#fff}</style></head><body>
<pre id="out"></pre><script>
window.__work = {
  arrays: function(n){
    var a=[]; for(var i=0;i<n;i++) a.push((i*2654435761)%1000003);
    a.sort(function(x,y){return x-y;});
    var s=0; for(var i=0;i<a.length;i++) s+=a[i];
    return s;
  },
  objects: function(n){
    var list=[]; for(var i=0;i<n;i++) list.push({id:i,name:'item-'+i,value:i*0.5});
    var total=0; for(var i=0;i<list.length;i++) total+=list[i].id+list[i].value;
    return total;
  },
  strings: function(n){
    var parts=[]; for(var i=0;i<n;i++) parts.push('chunk-'+i+'-');
    var text=parts.join(''); var hash=0;
    for(var i=0;i<text.length;i+=97) hash=(hash*31+text.charCodeAt(i))|0;
    return hash;
  },
  json: function(n){
    var list=[]; for(var i=0;i<n;i++) list.push({id:i,name:'item-'+i,tags:['a','b','c'],value:i*0.25});
    var text=JSON.stringify(list);
    var parsed=JSON.parse(text);
    return parsed.length;
  },
  typed: function(n){
    var a=new Int32Array(n);
    for(var i=0;i<n;i++) a[i]=(i*2654435761)|0;
    var s=0; for(var i=0;i<n;i++) s+=a[i];
    return s;
  },
  regex: function(n){
    var parts=[]; for(var i=0;i<n;i++) parts.push('item-'+i);
    var text=parts.join(' ');
    var m=text.match(/item-(\d+)/g);
    return m?m.length:0;
  },
  mapset: function(n){
    var m=new Map(), s=new Set();
    for(var i=0;i<n;i++){ m.set('k'+i,i); s.add(i%1000); }
    var t=0; m.forEach(function(v){ t+=v; });
    return t+s.size;
  },
  sortstrings: function(n){
    var a=[]; for(var i=0;i<n;i++) a.push('s'+(n-i));
    a.sort(); return a.length;
  },
  fib: function(n){
    function f(k){ return k<2?k:f(k-1)+f(k-2); }
    return f(n);
  },
  math: function(n){
    var s=0; for(var i=0;i<n;i++) s+=Math.sqrt(i)+Math.sin(i)+Math.cos(i);
    return s;
  },
  dates: function(n){
    var s=0; for(var i=0;i<n;i++){ var d=new Date(i*1000); s+=d.getTime()%1000; }
    return s;
  },
  prototypes: function(n){
    function Item(id){ this.id=id; this.name='item-'+id; }
    Item.prototype.value=function(){ return this.id*0.5; };
    var s=0; for(var i=0;i<n;i++) s+=new Item(i).value();
    return s;
  },
  closures: function(n){
    var f=[]; for(var i=0;i<n;i++){ (function(x){ f.push(function(){ return x; }); })(i); }
    var s=0; for(var i=0;i<f.length;i++) s+=f[i]();
    return s;
  },
  generators: function(n){
    function* gen(){ for(var i=0;i<n;i++) yield i; }
    var s=0, it=gen(), v=it.next();
    while(!v.done){ s+=v.value; v=it.next(); }
    return s;
  },
  recursion: function(depth){
    function walk(d){ return d===0?1:walk(d-1)+walk(d-1); }
    return walk(depth);
  },
  jsondeep: function(n){
    var o={v:0}; for(var i=0;i<n;i++) o={v:i,next:o};
    var text=JSON.stringify(o);
    var p=JSON.parse(text), c=0;
    while(p){ c++; p=p.next; }
    return c;
  },
  arraybuffer: function(n){
    var b=new ArrayBuffer(n*4), v=new DataView(b);
    for(var i=0;i<n;i++) v.setInt32(i*4,i);
    var s=0; for(var i=0;i<n;i++) s+=v.getInt32(i*4);
    return s;
  }
};
</script></body></html>''';

String layoutPage(String mode, int count) {
  final css = StringBuffer(
    'html,body{margin:0;padding:0;font:13px sans-serif;background:#fff}'
    '#root{padding:8px}',
  );
  final body = StringBuffer();
  if (mode == 'flex') {
    css.write(
      '#root{display:flex;flex-wrap:wrap;gap:4px}'
      '.item{width:120px;height:32px;background:#eef2f7;border:1px solid #d9e1ea;'
      'line-height:32px;padding:0 6px;box-sizing:border-box}',
    );
    for (var i = 0; i < count; i++) {
      body.write('<div class="item">Item $i</div>');
    }
  } else if (mode == 'grid') {
    css.write(
      '#root{display:grid;grid-template-columns:repeat(20,1fr);gap:4px}'
      '.item{height:28px;background:#eef2f7;border:1px solid #d9e1ea;'
      'line-height:28px;padding:0 4px;box-sizing:border-box}',
    );
    for (var i = 0; i < count; i++) {
      body.write('<div class="item">$i</div>');
    }
  } else if (mode == 'table') {
    css.write(
      'table{border-collapse:collapse;width:100%}'
      'td{border:1px solid #d9e1ea;padding:4px 8px}'
      'tr:nth-child(even){background:#f6f8fb}',
    );
    body.write('<table id="root"><tbody>');
    for (var i = 0; i < count; i++) {
      body.write(
        '<tr><td>$i</td><td>alpha</td><td>beta</td><td>gamma</td></tr>',
      );
    }
    body.write('</tbody></table>');
  } else if (mode == 'cards') {
    css.write(
      '#root{font-size:0}'
      '.card{display:inline-block;vertical-align:top;width:180px;height:76px;'
      'margin:4px;padding:8px;border:1px solid #d9e1ea;background:#f8fafc;'
      'box-sizing:border-box;font-size:12px}'
      '.card b{display:block;margin-bottom:4px}',
    );
    for (var i = 0; i < count; i++) {
      body.write(
        '<div class="card"><b>Card $i</b><span>alpha beta gamma</span><br>'
        '<button>Action</button></div>',
      );
    }
  } else if (mode == 'text') {
    css.write('p{margin:0 0 8px;line-height:1.45}');
    for (var i = 0; i < count; i++) {
      body.write(
        '<p>Paragraph $i: alpha beta gamma delta epsilon zeta eta theta iota '
        'kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega.</p>',
      );
    }
  } else if (mode == 'nested') {
    css.write(
      '#root{display:flex;flex-wrap:wrap;gap:6px}'
      '.nested{padding:4px;border:1px solid #d9e1ea;background:#f8fafc}'
      '.nested .nested{background:#eef2f7}',
    );
    for (var i = 0; i < count; i++) {
      body.write('<div class="nested">$i ');
      for (var depth = 0; depth < 5; depth++) {
        body.write('<div class="nested">d$depth ');
      }
      body.write('leaf');
      for (var depth = 0; depth < 6; depth++) {
        body.write('</div>');
      }
    }
  } else if (mode == 'position') {
    css.write(
      '#root{position:relative;height:${(count / 20).ceil() * 90}px}'
      '.box{position:absolute;width:84px;height:40px;background:#eef2f7;'
      'border:1px solid #d9e1ea;line-height:40px;text-align:center}',
    );
    body.write('<div id="root">');
    for (var i = 0; i < count; i++) {
      final x = (i % 20) * 90;
      final y = (i ~/ 20) * 48;
      body.write('<div class="box" style="left:${x}px;top:${y}px">$i</div>');
    }
    body.write('</div>');
  } else if (mode == 'mixed') {
    css.write(
      '#root{font-size:0}'
      '.card{display:inline-block;vertical-align:top;width:220px;margin:4px;'
      'padding:8px;border:1px solid #d9e1ea;background:#f8fafc;font-size:12px}'
      'input{width:100%;box-sizing:border-box;margin:4px 0;padding:3px}',
    );
    for (var i = 0; i < count; i++) {
      body.write(
        '<div class="card"><b>Item $i</b><input value="value $i">'
        '<button>Save</button><p>alpha beta gamma</p></div>',
      );
    }
  }
  return '<!doctype html><html><head><meta charset="utf-8"><style>$css</style>'
      '</head><body><div id="root">$body</div></body></html>';
}

String horizontalPage(int count) {
  return '<!doctype html><html><head><meta charset="utf-8"><style>'
      'html,body{margin:0;padding:0;background:#fff;font:12px sans-serif}'
      '#root{display:flex;width:${count * 110}px;height:240px;gap:6px;padding:6px}'
      '.box{flex:0 0 100px;height:100px;background:#eef2f7;border:1px solid #d9e1ea}'
      '</style></head><body><div id="root">'
      '${[for (var i = 0; i < count; i++) '<div class="box">$i</div>'].join()}'
      '</div></body></html>';
}

String formPage(String mode, int count) {
  final items = StringBuffer();
  for (var i = 0; i < count; i++) {
    if (mode == 'selects') {
      items.write(
        '<label>Field $i <select><option>alpha</option><option>beta</option>'
        '<option>gamma</option></select></label>',
      );
    } else if (mode == 'checkboxes') {
      items.write('<label><input type="checkbox"> Option $i</label>');
    } else if (mode == 'labels') {
      items.write(
        '<div class="field"><label>Field $i</label><span>alpha beta</span></div>',
      );
    } else if (mode == 'validation') {
      items.write(
        '<label>Field $i <input required pattern="[A-Za-z]{3,}" value="ab">'
        '</label>',
      );
    } else {
      items.write('<label>Field $i <input value="value $i"></label>');
    }
  }
  return '<!doctype html><html><head><meta charset="utf-8"><style>'
      'html,body{margin:0;padding:8px;font:13px sans-serif;background:#fff}'
      '#root{display:flex;flex-wrap:wrap;gap:6px}'
      'label{display:inline-block;width:150px;margin:2px;padding:3px;'
      'border:1px solid #d9e1ea;background:#f8fafc}'
      'input,select{width:100%;box-sizing:border-box;margin-top:3px}'
      '.field{width:150px;margin:2px;padding:3px;border:1px solid #d9e1ea}'
      '</style></head><body><form id="root">$items</form></body></html>';
}

String animationPage(String mode, int count) {
  final css = StringBuffer(
    'html,body{margin:0;padding:8px;background:#fff;font:12px sans-serif}'
    '#root{display:flex;flex-wrap:wrap;gap:4px}'
    '.box{width:32px;height:32px;background:#7aa2ff;border-radius:4px}',
  );
  if (mode == 'keyframes' || mode == 'mixed') {
    css.write(
      '@keyframes pulse{from{transform:scale(0.6);background:#7aa2ff}'
      'to{transform:scale(1.2);background:#a371f7}}'
      '.box{animation:pulse 700ms infinite alternate}'
      '#root.play .box{animation-play-state:paused}',
    );
  }
  if (mode == 'transitions' || mode == 'transform' || mode == 'mixed') {
    css.write('.box{transition:transform 180ms ease, opacity 180ms ease}');
  }
  if (mode == 'opacity') {
    css.write('.box{transition:opacity 180ms ease}');
  }
  final boxes = StringBuffer();
  for (var i = 0; i < count; i++) {
    boxes.write('<div class="box"></div>');
  }
  return '<!doctype html><html><head><meta charset="utf-8"><style>$css</style>'
      '</head><body><div id="root">$boxes</div><script>'
      'window.__anim={'
      'toggle:function(){document.getElementById("root").classList.toggle("play");'
      'document.body.getBoundingClientRect();return 1;},'
      'mutate:function(){var els=document.querySelectorAll(".box");'
      'for(var i=0;i<els.length;i++){els[i].style.transform="rotate("+((i%8)*45)+"deg)";'
      'els[i].style.opacity=String((i%10)/10+0.1);}'
      'document.body.getBoundingClientRect();return els.length;},'
      'raf:function(){var t=0;for(var i=0;i<120;i++){'
      'var els=document.querySelectorAll(".box");'
      'if(els.length)els[i%els.length].style.transform="scale("+(1+(i%5)/10)+")";'
      't+=document.body.getBoundingClientRect().height;}return t;}'
      '};</script></body></html>';
}

String gamePage({
  required int width,
  required int height,
  required int particles,
}) =>
    '''<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:#05070a;overflow:hidden}
canvas{display:block;width:${width}px;height:${height}px}
</style></head><body>
<canvas id="game" width="$width" height="$height"></canvas>
<script>
window.__game = function(n) {
  var c = document.getElementById('game');
  var g = c.getContext('2d');
  g.fillStyle = '#05070a';
  g.fillRect(0, 0, c.width, c.height);
  for (var i = 0; i < n; i++) {
    var x = (i * 73 + 17) % c.width;
    var y = (i * 151 + 29) % c.height;
    var r = 2 + (i % 9);
    g.beginPath();
    g.fillStyle = 'hsl(' + ((i * 31) % 360) + ', 75%, 55%)';
    g.arc(x, y, r, 0, Math.PI * 2);
    g.fill();
  }
  return n;
};
</script></body></html>''';

String game3dPage({
  required int width,
  required int height,
  required int cubes,
}) =>
    '''<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:#05070a;overflow:hidden}
canvas{display:block;width:${width}px;height:${height}px}
</style></head><body>
<canvas id="game3d" width="$width" height="$height"></canvas>
<script>
(function(){
  var canvas = document.getElementById('game3d');
  var gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
  if (!gl) {
    window.__game3d = function(){ return -1; };
    window.__game3d_error = 'webgl unavailable';
    return;
  }
  window.__game3d = function(){ return -1; };
  var vs = 'attribute vec3 a_position; uniform mat4 u_projection; uniform float u_time;' +
    'varying float v_depth; void main(){ vec3 p=a_position;' +
    'float c=cos(u_time), s=sin(u_time); p.xz=mat2(c,-s,s,c)*p.xz;' +
    'vec4 outv=u_projection*vec4(p,1.0); v_depth=outv.z; gl_Position=outv; }';
  var fs = 'precision mediump float; varying float v_depth; void main(){' +
    'float t=clamp((v_depth+1.0)*0.5,0.0,1.0);' +
    'gl_FragColor=vec4(0.35+0.4*t,0.25+0.5*(1.0-t),0.9-0.4*t,1.0); }';
  function shader(type, source){
    var s=gl.createShader(type); gl.shaderSource(s,source); gl.compileShader(s);
    if(!gl.getShaderParameter(s,gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  }
  var program=gl.createProgram();
  gl.attachShader(program,shader(gl.VERTEX_SHADER,vs));
  gl.attachShader(program,shader(gl.FRAGMENT_SHADER,fs));
  gl.linkProgram(program);
  if(!gl.getProgramParameter(program,gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
  gl.useProgram(program);
  var pos=gl.getAttribLocation(program,'a_position');
  var uProjection=gl.getUniformLocation(program,'u_projection');
  var uTime=gl.getUniformLocation(program,'u_time');
  var cube=[
    -1,-1,-1, 1,-1,-1, 1,1,-1, -1,-1,-1, 1,1,-1, -1,1,-1,
    -1,-1,1, 1,1,1, 1,-1,1, -1,-1,1, -1,1,1, 1,1,1,
    -1,-1,-1, -1,1,-1, -1,1,1, -1,-1,-1, -1,1,1, -1,-1,1,
    1,-1,-1, 1,-1,1, 1,1,1, 1,-1,-1, 1,1,1, 1,1,-1,
    -1,-1,-1, -1,-1,1, 1,-1,1, -1,-1,-1, 1,-1,1, 1,-1,-1,
    -1,1,-1, 1,1,-1, 1,1,1, -1,1,-1, 1,1,1, -1,1,1
  ];
  var perCube=cube.length/3;
  var vertices=new Float32Array(${cubes}*perCube*3);
  var p=0;
  for(var i=0;i<${cubes};i++){
    var ox=((i%10)-5)*2.4;
    var oy=((Math.floor(i/10)%10)-5)*2.4;
    var oz=((Math.floor(i/100)%10)-5)*2.4;
    for(var j=0;j<cube.length;j+=3){
      vertices[p++]=cube[j]+ox;
      vertices[p++]=cube[j+1]+oy;
      vertices[p++]=cube[j+2]+oz;
    }
  }
  var buffer=gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
  gl.bufferData(gl.ARRAY_BUFFER,vertices,gl.STATIC_DRAW);
  gl.enableVertexAttribArray(pos);
  gl.vertexAttribPointer(pos,3,gl.FLOAT,false,0,0);
  function perspective(fovy,aspect,near,far){
    var f=1/Math.tan(fovy/2);
    return new Float32Array([
      f/aspect,0,0,0, 0,f,0,0, 0,0,(far+near)/(near-far),-1,
      0,0,(2*far*near)/(near-far),0
    ]);
  }
  var projection=perspective(Math.PI/3,canvas.width/canvas.height,0.1,200);
  gl.uniformMatrix4fv(uProjection,false,projection);
  gl.enable(gl.DEPTH_TEST);
  window.__game3d=function(n){
    gl.viewport(0,0,canvas.width,canvas.height);
    gl.clearColor(0.02,0.03,0.05,1);
    gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
    gl.uniform1f(uTime,0.35);
    gl.drawArrays(gl.TRIANGLES,0,Math.min(n,${cubes})*perCube);
    return n*perCube;
  };
})();
</script></body></html>''';

String canvasPage(int count) {
  return '<!doctype html><html><head><meta charset="utf-8"><style>'
      'html,body{margin:0;background:#fff}canvas{display:block}'
      '</style></head><body><canvas id="c" width="800" height="900"></canvas>'
      '<script>window.__draw=function(n){var c=document.getElementById("c");'
      'var g=c.getContext("2d");g.clearRect(0,0,c.width,c.height);'
      'for(var i=0;i<n;i++){g.fillStyle="hsl("+((i*17)%360)+",70%,55%)";'
      'g.fillRect((i*37)%780,(i*53)%880,18,18);}return n;};</script>'
      '</body></html>';
}

String blankPage() => '''<!doctype html><html><head><meta charset="utf-8">
<style>html,body{margin:0;padding:0;background:#fff}</style></head>
<body><div id="idle">idle</div></body></html>''';

String _shortCount(int value) {
  if (value >= 1000 && value % 1000 == 0) return '${value ~/ 1000}k';
  return '$value';
}

String _humanCount(int value) {
  if (value >= 1000 && value % 1000 == 0) {
    return '${(value ~/ 1000).toString().replaceAllMapped(RegExp(r'\\B(?=(\\d{3})+(?!\\d))'), (m) => ',')},000';
  }
  return '$value';
}

List<ScenarioOp> _scrollOps(int steps, {int dx = 0, int dy = 600}) => [
  for (var i = 0; i < steps; i++)
    ScenarioOp(
      'scroll-$i',
      'window.scrollBy($dx, $dy); document.documentElement.getBoundingClientRect();',
      scroll: true,
    ),
];

PerfScenario _rowsCreate(int count) => PerfScenario(
  id: 'dom.rows-create-${_shortCount(count)}',
  title: 'Create ${_humanCount(count)} rows',
  kind: ScenarioKind.dom,
  source: 'uibench / js-framework-benchmark / million-rows',
  description:
      'Append ${_humanCount(count)} identical rows in one fragment, then force layout.',
  pageBuilder: () => rowsPage(),
  ops: [ScenarioOp('create-${_shortCount(count)}', '__perf.create($count)')],
  expectedNodes: count + 2,
);

PerfScenario _rowsUpdate(int count) => PerfScenario(
  id: 'dom.rows-update-${_shortCount(count)}',
  title: 'Update every 10th of ${_humanCount(count)} rows',
  kind: ScenarioKind.dom,
  source: 'js-framework-benchmark (partial update)',
  description:
      'Create ${_humanCount(count)} rows during setup, then update every tenth row.',
  pageBuilder: () => rowsPage(initialRows: count),
  ops: [ScenarioOp('update-${_shortCount(count)}', '__perf.updateEvery(10)')],
  expectedNodes: count + 2,
);

PerfScenario _rowsRemove(int count) => PerfScenario(
  id: 'dom.rows-remove-${_shortCount(count)}',
  title: 'Remove ${_humanCount(count)} rows',
  kind: ScenarioKind.dom,
  source: 'js-framework-benchmark (remove all)',
  description:
      'Create ${_humanCount(count)} rows during setup, then remove all.',
  pageBuilder: () => rowsPage(initialRows: count),
  ops: [ScenarioOp('remove-${_shortCount(count)}', '__perf.removeAll()')],
  expectedNodes: 1,
);

PerfScenario _layoutScenario(
  String mode,
  int count, {
  ScenarioKind kind = ScenarioKind.dom,
  String prefix = 'dom',
}) => PerfScenario(
  id: '$prefix.$mode-create-${_shortCount(count)}',
  title:
      '${mode[0].toUpperCase()}${mode.substring(1)} layout: ${_humanCount(count)} items',
  kind: kind,
  source: 'layout stress (${mode})',
  description:
      'Build a ${mode} layout with ${_humanCount(count)} items and force one layout pass.',
  pageBuilder: () => layoutPage(mode, count),
  ops: [ScenarioOp('layout', 'document.body.getBoundingClientRect()')],
);

PerfScenario _formScenario(String mode, int count) => PerfScenario(
  id: 'form.${mode}-${_shortCount(count)}',
  title: 'Forms: ${_humanCount(count)} ${mode}',
  kind: ScenarioKind.dom,
  source: 'forms / controls stress',
  description:
      'Build ${_humanCount(count)} ${mode} controls and touch every control once.',
  pageBuilder: () => formPage(mode, count),
  ops: [
    ScenarioOp(mode, switch (mode) {
      'inputs' =>
        'var e=document.querySelectorAll("input");for(var i=0;i<e.length;i++)e[i].value="changed "+i;document.body.getBoundingClientRect()',
      'selects' =>
        'var e=document.querySelectorAll("select");for(var i=0;i<e.length;i++)e[i].selectedIndex=(i%3);document.body.getBoundingClientRect()',
      'checkboxes' =>
        'var e=document.querySelectorAll("input");for(var i=0;i<e.length;i++)e[i].checked=(i%2===0);document.body.getBoundingClientRect()',
      'validation' => 'document.getElementById("root").checkValidity()',
      _ => 'document.body.getBoundingClientRect()',
    }),
  ],
);

PerfScenario _jsScenario(
  String id,
  String title,
  String work,
  int count,
  String description,
) => PerfScenario(
  id: 'js.$id',
  title: '$title ($count)',
  kind: ScenarioKind.js,
  source: 'Browser-Bench / V8-style JS workloads',
  description: description,
  pageBuilder: jsPage,
  ops: [ScenarioOp(id, 'window.__work.$work($count)')],
);

PerfScenario _scrollScenario(
  String id,
  String title,
  int count,
  String Function() pageBuilder, {
  int dx = 0,
  int? dy,
  int steps = 20,
  int? expectedNodes,
}) => PerfScenario(
  id: 'scroll.$id',
  title: title,
  kind: ScenarioKind.scroll,
  source: 'PassMark 2D HTML Scroll / js-framework-benchmark',
  description:
      'Load $count items, then scroll $steps times and force layout on each step.',
  pageBuilder: pageBuilder,
  ops: _scrollOps(steps, dx: dx, dy: dy ?? 600),
  expectedNodes: expectedNodes,
);

PerfScenario _animationScenario(String mode, int count) => PerfScenario(
  id: 'animation.${mode}-${_shortCount(count)}',
  title: 'Animation: ${mode} with ${_humanCount(count)} boxes',
  kind: ScenarioKind.dom,
  source: 'CSS animation / paint stress',
  description:
      'Animate or mutate ${_humanCount(count)} boxes and force layout/paint work.',
  pageBuilder: () => animationPage(mode, count),
  ops: [
    ScenarioOp(
      mode,
      mode == 'raf'
          ? 'window.__anim.raf()'
          : mode == 'keyframes'
          ? 'window.__anim.toggle()'
          : 'window.__anim.mutate()',
    ),
  ],
);

PerfScenario _canvasScenario(int count) => PerfScenario(
  id: 'animation.canvas-${_shortCount(count)}',
  title: 'Canvas: draw ${_humanCount(count)} rectangles',
  kind: ScenarioKind.dom,
  source: 'Canvas 2D paint stress',
  description:
      'Clear an 800x900 canvas and draw ${_humanCount(count)} coloured rectangles.',
  pageBuilder: () => canvasPage(count),
  ops: [ScenarioOp('draw-${_shortCount(count)}', 'window.__draw($count)')],
);

final List<PerfScenario> builtInScenarios = [
  PerfScenario(
    id: 'idle.blank',
    title: 'Idle blank page',
    kind: ScenarioKind.idle,
    source: 'baseline',
    description:
        'Empty document held idle for 2.5 s. Measures resident memory and CPU without workload.',
    pageBuilder: blankPage,
    idleMs: 2500,
  ),
  PerfScenario(
    id: 'dom.rows-create-1k',
    title: 'Create 1,000 rows',
    kind: ScenarioKind.dom,
    source: 'uibench / js-framework-benchmark / million-rows',
    description:
        'Append 1,000 identical rows in one fragment, then force layout.',
    pageBuilder: () => rowsPage(),
    ops: [ScenarioOp('create-1k', '__perf.create(1000)')],
    expectedNodes: 1002,
  ),
  PerfScenario(
    id: 'dom.rows-create-10k',
    title: 'Create 10,000 rows',
    kind: ScenarioKind.dom,
    source: 'uibench / js-framework-benchmark / million-rows',
    description: 'Append 10,000 rows in one fragment, then force layout.',
    pageBuilder: () => rowsPage(),
    ops: [ScenarioOp('create-10k', '__perf.create(10000)')],
    expectedNodes: 10002,
  ),
  PerfScenario(
    id: 'dom.rows-update-10k',
    title: 'Update every 10th of 10,000 rows',
    kind: ScenarioKind.dom,
    source: 'js-framework-benchmark (partial update)',
    description:
        'Create 10,000 rows during setup, then update the text of every tenth row.',
    pageBuilder: () => rowsPage(initialRows: 10000),
    ops: [ScenarioOp('update', '__perf.updateEvery(10)')],
    expectedNodes: 10002,
  ),
  PerfScenario(
    id: 'dom.rows-remove-10k',
    title: 'Remove 10,000 rows',
    kind: ScenarioKind.dom,
    source: 'js-framework-benchmark (remove all)',
    description: 'Create 10,000 rows during setup, then remove all of them.',
    pageBuilder: () => rowsPage(initialRows: 10000),
    ops: [ScenarioOp('remove', '__perf.removeAll()')],
    expectedNodes: 1,
  ),
  PerfScenario(
    id: 'scroll.rows-10k',
    title: 'Scroll 10,000 rows',
    kind: ScenarioKind.scroll,
    source: 'PassMark 2D HTML Scroll / cerious-scroll',
    description:
        'Create 10,000 rows, then scroll 20 times and force layout on each step.',
    pageBuilder: () => rowsPage(initialRows: 10000),
    ops: [
      for (var i = 0; i < 20; i++)
        ScenarioOp(
          'scroll-$i',
          'window.scrollBy(0, 400); document.documentElement.getBoundingClientRect();',
          scroll: true,
        ),
    ],
    expectedNodes: 10002,
  ),
  PerfScenario(
    id: 'scroll.2d-tiles',
    title: '2D scroll over 900 tiles',
    kind: ScenarioKind.scroll,
    source: 'PassMark 2D HTML Scroll (equivalent scenario)',
    description:
        '900 absolutely positioned gradient tiles on a 6000x6000 board; 20 diagonal scroll steps.',
    notes: [
      'PassMark 2D HTML Scroll is proprietary and its benchmark page is not publicly redistributable; this scenario reproduces the same 2D scroll workload.',
    ],
    pageBuilder: () => rowsPage(twoD: true),
    ops: [
      for (var i = 0; i < 20; i++)
        ScenarioOp(
          'scroll-$i',
          'window.scrollBy(180, 160); document.documentElement.getBoundingClientRect();',
          scroll: true,
        ),
    ],
    expectedNodes: 902,
  ),
  PerfScenario(
    id: 'js.arrays',
    title: 'JS arrays: build, sort, sum',
    kind: ScenarioKind.js,
    source: 'Browser-Bench (JS responsiveness)',
    description:
        'Sort 100,000 numbers and sum them; checksum returned by the page.',
    pageBuilder: jsPage,
    ops: [ScenarioOp('arrays', 'window.__work.arrays(100000)')],
  ),
  PerfScenario(
    id: 'js.objects',
    title: 'JS objects: 50,000 allocations',
    kind: ScenarioKind.js,
    source: 'Browser-Bench (JS responsiveness)',
    description: 'Allocate 50,000 objects and read every property back.',
    pageBuilder: jsPage,
    ops: [ScenarioOp('objects', 'window.__work.objects(50000)')],
  ),
  PerfScenario(
    id: 'js.strings',
    title: 'JS strings: join and hash',
    kind: ScenarioKind.js,
    source: 'Browser-Bench (JS responsiveness)',
    description: 'Join 50,000 chunks and hash the resulting string.',
    pageBuilder: jsPage,
    ops: [ScenarioOp('strings', 'window.__work.strings(50000)')],
  ),
  PerfScenario(
    id: 'js.json',
    title: 'JS JSON: stringify + parse',
    kind: ScenarioKind.js,
    source: 'Browser-Bench (JS responsiveness)',
    description: 'Stringify and re-parse 20,000 objects.',
    pageBuilder: jsPage,
    ops: [ScenarioOp('json', 'window.__work.json(20000)')],
  ),
  for (final count in [100, 250, 500, 2000, 5000, 20000, 50000])
    _rowsCreate(count),
  for (final count in [100, 1000, 5000]) _rowsUpdate(count),
  for (final count in [100, 1000]) _rowsRemove(count),
  for (final count in [1000, 5000]) _layoutScenario('cards', count),
  _layoutScenario('table', 1000),
  for (final count in [1000, 5000]) _layoutScenario('flex', count),
  for (final count in [1000, 5000]) _layoutScenario('grid', count),
  _layoutScenario('nested', 1000),
  _formScenario('inputs', 1000),
  _layoutScenario('text', 5000),
  _layoutScenario('position', 1000),
  for (final count in [1000, 5000, 20000, 50000])
    _scrollScenario(
      'rows-${_shortCount(count)}',
      'Scroll ${_humanCount(count)} rows',
      count,
      () => rowsPage(initialRows: count),
      expectedNodes: count + 2,
    ),
  for (final tiles in [225, 400, 1600, 2500])
    _scrollScenario(
      '2d-tiles-${_shortCount(tiles)}',
      '2D scroll over $tiles tiles',
      tiles,
      () => rowsPage(twoD: true, tiles: tiles),
      dx: 180,
      dy: 160,
      expectedNodes: tiles + 2,
    ),
  for (final count in [1000, 5000])
    _scrollScenario(
      'horizontal-${_shortCount(count)}',
      'Horizontal scroll over ${_humanCount(count)} boxes',
      count,
      () => horizontalPage(count),
      dx: 420,
      dy: 0,
      expectedNodes: count + 2,
    ),
  _scrollScenario(
    'table-1k',
    'Scroll a 1,000-row table',
    1000,
    () => layoutPage('table', 1000),
  ),
  _scrollScenario(
    'cards-2k',
    'Scroll 2,000 cards',
    2000,
    () => layoutPage('cards', 2000),
  ),
  _scrollScenario(
    'forms-1k',
    'Scroll 1,000 form fields',
    1000,
    () => formPage('inputs', 1000),
  ),
  _scrollScenario(
    'text-5k',
    'Scroll 5,000 paragraphs',
    5000,
    () => layoutPage('text', 5000),
  ),
  _scrollScenario(
    'nested-1k',
    'Scroll 1,000 nested boxes',
    1000,
    () => layoutPage('nested', 1000),
  ),
  for (final count in [10000, 500000])
    _jsScenario(
      'arrays-${_shortCount(count)}',
      'JS arrays: build, sort, sum',
      'arrays',
      count,
      'Sort $count numbers and sum them.',
    ),
  for (final count in [5000, 100000])
    _jsScenario(
      'objects-${_shortCount(count)}',
      'JS objects: allocations',
      'objects',
      count,
      'Allocate $count objects and read every property back.',
    ),
  for (final count in [5000, 100000])
    _jsScenario(
      'strings-${_shortCount(count)}',
      'JS strings: join and hash',
      'strings',
      count,
      'Join $count chunks and hash the resulting string.',
    ),
  for (final count in [5000, 50000])
    _jsScenario(
      'json-${_shortCount(count)}',
      'JS JSON: stringify + parse',
      'json',
      count,
      'Stringify and re-parse $count objects.',
    ),
  _jsScenario(
    'typed-arrays',
    'JS typed arrays',
    'typed',
    500000,
    'Fill and sum an Int32Array of 500,000 elements.',
  ),
  _jsScenario(
    'regex',
    'JS regular expressions',
    'regex',
    20000,
    'Build 20,000 matches with a global regular expression.',
  ),
  _jsScenario(
    'map-set',
    'JS Map and Set',
    'mapset',
    100000,
    'Insert 100,000 keys into Map and Set and read them back.',
  ),
  _jsScenario(
    'sort-strings',
    'JS string sort',
    'sortstrings',
    50000,
    'Sort 50,000 generated strings.',
  ),
  _jsScenario(
    'fib',
    'JS recursion: Fibonacci',
    'fib',
    27,
    'Recursive Fibonacci(27).',
  ),
  _jsScenario(
    'math',
    'JS Math loop',
    'math',
    200000,
    'Run 200,000 sqrt/sin/cos operations.',
  ),
  _jsScenario(
    'dates',
    'JS Date parsing',
    'dates',
    20000,
    'Create and stringify 20,000 Date objects.',
  ),
  _jsScenario(
    'prototypes',
    'JS prototypes',
    'prototypes',
    100000,
    'Create 100,000 constructor instances and read their fields.',
  ),
  _jsScenario(
    'closures',
    'JS closures',
    'closures',
    50000,
    'Create 50,000 closures and invoke each one.',
  ),
  _jsScenario(
    'generators',
    'JS generators',
    'generators',
    100000,
    'Consume 100,000 values from a generator.',
  ),
  _jsScenario(
    'recursion-tree',
    'JS recursive tree',
    'recursion',
    15,
    'Walk a recursive tree of depth 15.',
  ),
  _jsScenario(
    'json-deep',
    'JS deeply nested JSON',
    'jsondeep',
    200,
    'Stringify and parse a 1,000-level nested JSON tree.',
  ),
  _jsScenario(
    'arraybuffer',
    'JS ArrayBuffer + DataView',
    'arraybuffer',
    500000,
    'Write and read 500,000 Int32 values through DataView.',
  ),
  for (final count in [100, 1000, 5000])
    _layoutScenario('flex', count, prefix: 'layout'),
  for (final count in [100, 1000, 5000])
    _layoutScenario('grid', count, prefix: 'layout'),
  _layoutScenario('table', 100, prefix: 'layout'),
  _layoutScenario('table', 1000, prefix: 'layout'),
  _layoutScenario('mixed', 1000, prefix: 'layout'),
  _layoutScenario('text', 1000, prefix: 'layout'),
  _formScenario('selects', 500),
  _formScenario('checkboxes', 1000),
  _formScenario('labels', 1000),
  _formScenario('validation', 1000),
  _formScenario('inputs', 5000),
  for (final count in [100, 1000]) _animationScenario('keyframes', count),
  _animationScenario('transitions', 1000),
  _animationScenario('transform', 1000),
  _animationScenario('opacity', 1000),
  _animationScenario('raf', 100),
  _canvasScenario(100),
  _canvasScenario(1000),
  _animationScenario('mixed', 1000),
  // 120-case matrix added for broad size/complexity coverage. These keep the
  // same page builders as the baseline cases but exercise different budgets.
  for (final count in [
    10,
    20,
    30,
    40,
    60,
    80,
    120,
    160,
    200,
    300,
    400,
    600,
    800,
    1200,
    1500,
    2500,
    3000,
    4000,
    6000,
    8000,
    12000,
    15000,
    25000,
    40000,
  ])
    _rowsCreate(count),
  for (final count in [
    10,
    20,
    30,
    40,
    60,
    80,
    120,
    160,
    200,
    300,
    400,
    600,
    800,
    1200,
    1500,
    2500,
    3000,
    4000,
    6000,
    8000,
    12000,
    15000,
    25000,
    40000,
  ])
    _rowsUpdate(count),
  for (final count in [
    10,
    20,
    30,
    40,
    60,
    80,
    120,
    160,
    200,
    300,
    400,
    600,
    800,
    1200,
    1500,
    2500,
    3000,
    4000,
    6000,
    8000,
    12000,
    15000,
    25000,
    40000,
  ])
    _rowsRemove(count),
  for (final count in [
    10,
    20,
    30,
    40,
    60,
    80,
    120,
    160,
    200,
    300,
    400,
    600,
    800,
    1200,
    1500,
    2500,
    3000,
    4000,
    6000,
    8000,
    12000,
    15000,
    25000,
    40000,
  ])
    _scrollScenario(
      'rows-${_shortCount(count)}',
      'Scroll ${_humanCount(count)} rows (matrix)',
      count,
      () => rowsPage(initialRows: count),
      expectedNodes: count + 2,
    ),
  for (final count in [
    10,
    20,
    50,
    200,
    400,
    800,
    1200,
    2000,
    3000,
    4000,
    8000,
    12000,
  ])
    _layoutScenario('flex', count, prefix: 'matrix'),
  for (final count in [10, 25, 50, 200, 500, 1200, 2500, 5000, 8000, 12000])
    _layoutScenario('grid', count, prefix: 'matrix'),
  _layoutScenario('table', 500, prefix: 'matrix'),
  _layoutScenario('mixed', 500, prefix: 'matrix'),
  for (final resolution in [
    (640, 360),
    (854, 480),
    (1280, 720),
    (1920, 1080),
    (2560, 1440),
  ])
    for (final particles in [100, 500, 1000, 2500, 5000])
      PerfScenario(
        id: 'game.quality-${resolution.$1}x${resolution.$2}-p$particles',
        title:
            'Game quality ${resolution.$1}x${resolution.$2} · $particles particles',
        kind: ScenarioKind.dom,
        source: 'game-player quality profiles',
        description:
            'Canvas 2D game frame at ${resolution.$1}x${resolution.$2} with $particles particles.',
        pageBuilder: () => gamePage(
          width: resolution.$1,
          height: resolution.$2,
          particles: particles,
        ),
        ops: [ScenarioOp('frame', 'window.__game($particles)')],
      ),
  for (final resolution in [
    (640, 360),
    (854, 480),
    (1280, 720),
    (1920, 1080),
    (2560, 1440),
  ])
    for (final cubes in [100, 500, 1000, 2500, 5000])
      PerfScenario(
        id: 'game3d.quality-${resolution.$1}x${resolution.$2}-c$cubes',
        title: '3D game ${resolution.$1}x${resolution.$2} · $cubes cubes',
        kind: ScenarioKind.dom,
        source: 'game-player 3D quality profiles',
        description:
            'WebGL cube scene at ${resolution.$1}x${resolution.$2} with $cubes cubes and perspective.',
        pageBuilder: () => game3dPage(
          width: resolution.$1,
          height: resolution.$2,
          cubes: cubes,
        ),
        ops: [ScenarioOp('frame', 'window.__game3d($cubes)')],
      ),
];

/// External scenarios. They are only run when their pinned suite is resolved.
List<PerfScenario> externalScenarios(List<ExternalSuite> suites) {
  final available = {for (final s in suites) s.id: s};
  final out = <PerfScenario>[];
  final browser = available['browserbench'];
  if (browser != null) {
    out.add(
      const PerfScenario(
        id: 'external.browserbench-quick',
        title: 'Browser-Bench quick run',
        kind: ScenarioKind.external,
        source: 'https://dinithaw.github.io/Browser-Bench/',
        description:
            "Runs the page's own Quick Run (600 ms per workload, 1 rep) and reads window.__lastRun.",
        externalId: 'browserbench',
        startJs: "document.getElementById('quick').click();",
        waitJs: '!!window.__lastRun',
        readJs: 'JSON.stringify(window.__lastRun)',
        timeoutMs: 30000,
      ),
    );
  }
  final jsfb = available['jsfb'];
  if (jsfb != null) {
    out.addAll(const [
      PerfScenario(
        id: 'external.jsfb-create-1k',
        title: 'js-framework-benchmark: create 1,000 rows',
        kind: ScenarioKind.external,
        source: 'https://github.com/krausest/js-framework-benchmark',
        description:
            'Clicks "Create 1,000 rows" in the official vanilla keyed implementation.',
        externalId: 'jsfb',
        startJs: "document.getElementById('run').click();",
        waitJs: "document.querySelectorAll('#tbody tr').length === 1000",
        readJs:
            "JSON.stringify({rows: document.querySelectorAll('#tbody tr').length})",
        timeoutMs: 30000,
      ),
      PerfScenario(
        id: 'external.jsfb-create-10k',
        title: 'js-framework-benchmark: create 10,000 rows',
        kind: ScenarioKind.external,
        source: 'https://github.com/krausest/js-framework-benchmark',
        description:
            'Clicks "Create 10,000 rows" in the official vanilla keyed implementation.',
        externalId: 'jsfb',
        startJs: "document.getElementById('runlots').click();",
        waitJs: "document.querySelectorAll('#tbody tr').length === 10000",
        readJs:
            "JSON.stringify({rows: document.querySelectorAll('#tbody tr').length})",
        timeoutMs: 30000,
      ),
      PerfScenario(
        id: 'external.jsfb-clear',
        title: 'js-framework-benchmark: clear 10,000 rows',
        kind: ScenarioKind.external,
        source: 'https://github.com/krausest/js-framework-benchmark',
        description: 'Creates 10,000 rows during setup, then clicks Clear.',
        externalId: 'jsfb',
        setupJs: "document.getElementById('runlots').click();",
        setupWaitJs: "document.querySelectorAll('#tbody tr').length === 10000",
        startJs: "document.getElementById('clear').click();",
        waitJs: "document.querySelectorAll('#tbody tr').length === 0",
        readJs:
            "JSON.stringify({rows: document.querySelectorAll('#tbody tr').length})",
        timeoutMs: 30000,
      ),
    ]);
  }
  for (final suite in suites) {
    if (suite.id == 'browserbench' || suite.id == 'jsfb') continue;
    out.add(
      PerfScenario(
        id: 'external.${suite.id}-load-scroll',
        title: '${suite.title}: load + scroll',
        kind: ScenarioKind.external,
        source: suite.url,
        description:
            'Loads the real benchmark page, counts nodes and scrolls through it 15 times.',
        externalId: suite.id,
        ops: [
          for (var i = 0; i < 15; i++)
            ScenarioOp(
              'scroll-$i',
              'window.scrollBy(0, 600); document.documentElement.getBoundingClientRect();',
              scroll: true,
            ),
        ],
        timeoutMs: 90000,
        notes: [
          if (suite.license.contains('no license'))
            'Upstream has no license file; fetched at runtime and not redistributed.',
        ],
      ),
    );
  }
  return out;
}

List<PerfScenario> allScenarios(List<ExternalSuite> suites) => [
  ...builtInScenarios,
  ...externalScenarios(suites),
];
