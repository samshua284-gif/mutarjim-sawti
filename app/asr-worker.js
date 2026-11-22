// عامل السمع: Whisper-small (مكمّى) عبر Transformers.js — من أصول التطبيق المحلية فقط.
// يعمل في خيط خلفي كي لا تتجمد الواجهة أثناء التعرف على الكلام.
// إصلاح 1.1: num_beams=1 بدل 2 — قياس الخادم على 5 عيّنات صوتية أعطى نصوصًا
// مطابقة حرفيًا في الإعدادين وبزمن أقل ~30% مع الجشع (62.0s مقابل 88.8s).
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
    pipePromise = pipeline('automatic-speech-recognition', 'whisper-small', {
      quantized: true,
      progress_callback: function (p) {
        self.postMessage({ type: 'progress', engine: 'asr', status: p.status, file: p.file, progress: p.progress });
      }
    });
  }
  return pipePromise;
}

self.onmessage = function (e) {
  var d = e.data || {};
  if (d.type === 'load') {
    load().then(function () {
      self.postMessage({ type: 'ready', engine: 'asr' });
    }).catch(function (err) {
      pipePromise = null;
      self.postMessage({ type: 'load-error', engine: 'asr', message: String((err && err.message) || err) });
    });
    return;
  }
  if (d.type === 'asr') {
    load().then(function (pipe) {
      // اللغة مفروضة من اختيار الطرف المتكلم — لا اكتشاف تلقائي (يخطئ بين الهندية والأردية)
      return pipe(d.audio, {
        language: d.whisperLang,
        task: 'transcribe',
        num_beams: 1,
        chunk_length_s: 30,
        stride_length_s: 5
      });
    }).then(function (out) {
      self.postMessage({ type: 'asr-done', id: d.id, text: ((out && out.text) || '').trim() });
    }).catch(function (err) {
      self.postMessage({ type: 'asr-error', id: d.id, message: String((err && err.message) || err) });
    });
  }
};
