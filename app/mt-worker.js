// عامل الترجمة: NLLB-200-distilled-600M (مكمّى) عبر Transformers.js — ترجمة مباشرة
// بين اللغات الأربع بلا وسيط إنجليزي، من أصول التطبيق المحلية فقط.
//
// إصلاح 1.1 (بعد اختبار الهاتف): الترجمة جملة-بجملة حصرًا، بلا أي دمج.
// السبب الجذري المُثبت بإعادة الإنتاج على الخادم: دمج عدة جمل في قطعة واحدة
// (≤350 حرفًا كما في 1.0) يجعل NLLB يُسقط جملًا كاملة بصمت من داخل القطعة
// (سقطت «أين أنتم؟» و"How are you?" في الإدخالين الفاشلين، وأُعيد إنتاجهما حرفيًا).
// ومع كل جملة: حارس اكتمال — نتيجة فارغة تُعاد ترجمتها مرة، فإن بقيت فارغة
// يُمرَّر نص الجملة الأصلي نفسه بدل إسقاطها. لا سقوط صامت أبدًا.
// خيارات التوليد: الافتراضية (= جشعة num_beams=1 فعليًا) — قياس 1.1 أثبت أن
// num_beams=2 أبطأ ~3 مرات ولا يمنع الإسقاط ولا يحسّن الجودة هنا.
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

// تقسيم النص إلى وحدات ترجمة: جُمل، وأي جملة أطول من 400 حرف تُقسَّم عند
// فاصلة عربية أو مسافة (كما في 1.0) — لكن كل وحدة تُترجم وحدها وتُحاسَب وحدها.
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

function translateOnce(pipe, unit, srcLang, tgtLang) {
  return pipe(unit, { src_lang: srcLang, tgt_lang: tgtLang }).then(function (r) {
    return ((r && r[0] && r[0].translation_text) || '').trim();
  }).catch(function () { return ''; });
}

// ترجمة وحدة واحدة مع حارس الاكتمال: محاولة، فإعادة عند الفراغ/الفشل،
// فتمرير النص الأصلي نفسه (مرئيًا في النتيجة) بدل إسقاطه بصمت.
function translateUnit(pipe, unit, srcLang, tgtLang) {
  return translateOnce(pipe, unit, srcLang, tgtLang).then(function (first) {
    if (first) return first;
    return translateOnce(pipe, unit, srcLang, tgtLang).then(function (second) {
      return second || unit;
    });
  });
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
      var units = splitSentences(d.text);
      var out = [];
      var chain = Promise.resolve();
      units.forEach(function (u) {
        chain = chain.then(function () {
          return translateUnit(pipe, u, d.srcLang, d.tgtLang).then(function (r) { out.push(r); });
        });
      });
      return chain.then(function () {
        // حارس أخير: عدد وحدات الخرج يساوي عدد وحدات الدخل ببنية التصميم،
        // وأي خرج كلي فارغ لدخل غير فارغ يُستبدل بالدخل نفسه — لا نتيجة فارغة صامتة.
        var result = out.join(' ');
        if (!result.trim() && String(d.text).trim()) result = String(d.text);
        return result;
      });
    }).then(function (result) {
      self.postMessage({ type: 'mt-done', id: d.id, result: result });
    }).catch(function (err) {
      self.postMessage({ type: 'mt-error', id: d.id, message: String((err && err.message) || err) });
    });
  }
};
