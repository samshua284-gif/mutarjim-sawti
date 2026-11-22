// عامل الترجمة: NLLB-200-distilled-600M (مكمّى) عبر Transformers.js — ترجمة مباشرة
// بين اللغات الأربع بلا وسيط إنجليزي، من أصول التطبيق المحلية فقط.
import { pipeline, env } from './transformers.min.js';

var BASE = new URL('./', self.location.href).href; // .../engines/
env.allowRemoteModels = false;
env.allowLocalModels = true;
env.localModelPath = BASE + 'models/';
if (env.backends && env.backends.onnx && env.backends.onnx.wasm) {
  env.backends.onnx.wasm.wasmPaths = BASE;
  env.backends.onnx.wasm.numThreads = Math.min(4, self.navigator.hardwareConcurrency || 2);
}

var pipePromise = null;
function load() {
  if (!pipePromise) {
    pipePromise = pipeline('translation', 'nllb-200-distilled-600M', {
      quantized: true,
      progress_callback: function (p) {
        self.postMessage({ type: 'progress', engine: 'mt', status: p.status, file: p.file, progress: p.progress });
      }
    });
  }
  return pipePromise;
}

// تقسيم النص الطويل إلى جمل ثم دمجها في أجزاء ≤350 حرفًا (سياق أتمّ واستدعاءات أقل)
function splitSentences(t) {
  var raw = String(t).split(/(?<=[.!?؟।])\s+|\n+/);
  var out = [];
  for (var i = 0; i < raw.length; i++) {
    var s = raw[i].trim();
    while (s.length > 400) {
      var cut = s.lastIndexOf('،', 400);
      if (cut < 150) cut = s.lastIndexOf(' ', 400);
      if (cut < 150) cut = 400;
      out.push(s.slice(0, cut).trim());
      s = s.slice(cut).trim();
    }
    if (s) out.push(s);
  }
  return out.length ? out : [String(t)];
}
function mergeChunks(parts) {
  var out = [];
  var cur = '';
  parts.forEach(function (s) {
    if (!cur) { cur = s; return; }
    if ((cur + ' ' + s).length <= 350) cur += ' ' + s;
    else { out.push(cur); cur = s; }
  });
  if (cur) out.push(cur);
  return out;
}

self.onmessage = function (e) {
  var d = e.data || {};
  if (d.type === 'load') {
    load().then(function () {
      self.postMessage({ type: 'ready', engine: 'mt' });
    }).catch(function (err) {
      pipePromise = null;
      self.postMessage({ type: 'load-error', engine: 'mt', message: String((err && err.message) || err) });
    });
    return;
  }
  if (d.type === 'mt') {
    load().then(function (pipe) {
      var chunks = mergeChunks(splitSentences(d.text));
      var out = [];
      var chain = Promise.resolve();
      chunks.forEach(function (ch) {
        chain = chain.then(function () {
          return pipe(ch, { src_lang: d.srcLang, tgt_lang: d.tgtLang }).then(function (r) {
            out.push((r && r[0] && r[0].translation_text) || ch);
          }).catch(function () { out.push(ch); });
        });
      });
      return chain.then(function () { return out.join(' '); });
    }).then(function (result) {
      self.postMessage({ type: 'mt-done', id: d.id, result: result });
    }).catch(function (err) {
      self.postMessage({ type: 'mt-error', id: d.id, message: String((err && err.message) || err) });
    });
  }
};
