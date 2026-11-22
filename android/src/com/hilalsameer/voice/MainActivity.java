package com.hilalsameer.voice;

import android.Manifest;
import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.net.Uri;
import android.os.Bundle;
import android.util.Base64;
import android.util.Log;
import android.webkit.ConsoleMessage;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.speech.tts.Voice;
import com.k2fsa.sherpa.onnx.FeatureConfig;
import com.k2fsa.sherpa.onnx.GeneratedAudio;
import com.k2fsa.sherpa.onnx.OfflineModelConfig;
import com.k2fsa.sherpa.onnx.OfflineRecognizer;
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig;
import com.k2fsa.sherpa.onnx.OfflineStream;
import com.k2fsa.sherpa.onnx.OfflineTts;
import com.k2fsa.sherpa.onnx.OfflineWhisperModelConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import org.json.JSONObject;

public class MainActivity extends Activity {
  private WebView w;
  private VoiceBridge bridge;
  private PermissionRequest pendingReq;
  private static final int MIC_REQ = 2001;
  private static final String HOST = "app.voice";
  private static final String TAG = "VOICE";

  private static final Map<String, String> MIME = new HashMap<>();
  static {
    MIME.put("html", "text/html");
    MIME.put("js", "text/javascript");
    MIME.put("mjs", "text/javascript");
    MIME.put("json", "application/json");
    MIME.put("wasm", "application/wasm");
    MIME.put("svg", "image/svg+xml");
    MIME.put("png", "image/png");
    MIME.put("jpg", "image/jpeg");
    MIME.put("css", "text/css");
    MIME.put("txt", "text/plain");
    MIME.put("onnx", "application/octet-stream");
  }

  @Override protected void onCreate(Bundle s) {
    super.onCreate(s);
    w = new WebView(this);
    WebSettings st = w.getSettings();
    st.setJavaScriptEnabled(true);
    st.setDomStorageEnabled(true);
    st.setDatabaseEnabled(true);
    st.setAllowFileAccess(true);
    st.setAllowFileAccessFromFileURLs(true);
    st.setAllowUniversalAccessFromFileURLs(true);
    st.setAllowContentAccess(true);
    st.setMediaPlaybackRequiresUserGesture(false);
    bridge = new VoiceBridge();
    w.addJavascriptInterface(bridge, "VoiceBridge");
    w.setWebViewClient(new WebViewClient() {
      @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
        Uri url = request.getUrl();
        if (url != null && HOST.equals(url.getHost())) {
          String path = url.getPath();
          if (path == null || path.equals("/")) path = "/index.html";
          String asset = "www" + path;
          Map<String, String> headers = new HashMap<>();
          headers.put("Cross-Origin-Opener-Policy", "same-origin");
          headers.put("Cross-Origin-Embedder-Policy", "credentialless");
          headers.put("Cross-Origin-Resource-Policy", "same-origin");
          try {
            InputStream is = getAssets().open(asset);
            String ext = "";
            int dot = asset.lastIndexOf('.');
            if (dot >= 0) ext = asset.substring(dot + 1).toLowerCase();
            String mime = MIME.containsKey(ext) ? MIME.get(ext) : "application/octet-stream";
            boolean text = mime.startsWith("text/") || mime.equals("application/json");
            return new WebResourceResponse(mime, text ? "UTF-8" : null, 200, "OK", headers, is);
          } catch (Exception e) {
            Log.w(TAG, "asset miss: " + asset);
            return new WebResourceResponse("text/plain", "UTF-8", 404, "Not Found", headers,
                new java.io.ByteArrayInputStream(new byte[0]));
          }
        }
        return super.shouldInterceptRequest(view, request);
      }
    });
    w.setWebChromeClient(new WebChromeClient() {
      @Override public boolean onConsoleMessage(ConsoleMessage m) {
        Log.d(TAG, "web: " + m.message());
        return true;
      }
      @Override public void onPermissionRequest(final PermissionRequest request) {
        boolean wantsAudio = false;
        for (String r : request.getResources()) {
          if (PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(r)) wantsAudio = true;
        }
        if (!wantsAudio) { request.deny(); return; }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
          request.grant(new String[]{PermissionRequest.RESOURCE_AUDIO_CAPTURE});
        } else {
          pendingReq = request;
          requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, MIC_REQ);
        }
      }
      @Override public void onPermissionRequestCanceled(PermissionRequest request) {
        if (pendingReq == request) pendingReq = null;
      }
    });
    setContentView(w);
    w.loadUrl("https://" + HOST + "/index.html");
    // تجهيز بيانات espeak في الخلفية لتسريع أول نطق
    new Thread(() -> {
      try { VoiceBridge.extractEspeak(MainActivity.this); } catch (Throwable ignored) {}
    }).start();
    // تهيئة صوت نظام الهاتف (مسار نطق ثانٍ للعربية فقط، 1.3): يفحص الجسر توفر
    // صوت عربي فعلي على الجهاز ويُعلم الصفحة عند الجاهزية.
    bridge.ensureSysTts();
    // تسخين السمع الأصلي في الخلفية (1.4): استخراج ملفات
    // Whisper بصيغة sherpa وبناء المعرّف، كي تكون الأذن جاهزة
    // عند أول تسجيل.
    new Thread(() -> {
      try { bridge.warmAsr(); } catch (Throwable ignored) {}
    }).start();
  }

  @Override public void onRequestPermissionsResult(int req, String[] perms, int[] results) {
    super.onRequestPermissionsResult(req, perms, results);
    if (req == MIC_REQ && pendingReq != null) {
      if (results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) {
        pendingReq.grant(new String[]{PermissionRequest.RESOURCE_AUDIO_CAPTURE});
      } else {
        pendingReq.deny();
      }
      pendingReq = null;
    }
  }

  void evalTtsCallback(int id, boolean ok, String err) {
    evalTtsCallback(id, ok, err, null);
  }

  // ردّ نداء النطق مع الصوت الذي نطق فعلًا (1.5): يمرَّر معرّف الصوت الخادم
  // إلى الصفحة فتعرضه في سطر «الصوت المستعمل» داخل مربع الطرف صاحب الصوت —
  // دليل من الجهاز نفسه على أي نموذج نطق العبارة، لا مجرد ما اختير في القائمة.
  void evalTtsCallback(int id, boolean ok, String err, String voice) {
    String js = "window.__ttsCallback && window.__ttsCallback(" + id + "," + ok + ","
        + JSONObject.quote(err == null ? "" : err) + ","
        + (voice == null ? "null" : JSONObject.quote(voice)) + ")";
    w.evaluateJavascript(js, null);
  }

  // ردّ نداء السمع الأصلي (1.4): الحمولة هي النص المتعرّف عليه عند النجاح
  // أو رسالة الخطأ عند الفشل (عندها تسقط الصفحة إلى عامل الويب تلقائيًا).
  void evalAsrCallback(int id, boolean ok, String payload) {
    String js = "window.__asrCallback && window.__asrCallback(" + id + "," + ok + ","
        + JSONObject.quote(payload == null ? "" : payload) + ")";
    w.evaluateJavascript(js, null);
  }

  @Override public void onBackPressed() {
    if (w != null && w.canGoBack()) w.goBack(); else super.onBackPressed();
  }

  @Override protected void onDestroy() {
    if (bridge != null) bridge.shutdownSysTts();
    super.onDestroy();
  }

  /* ================= جسر النطق والنسخ ================= */
  public class VoiceBridge {
    private volatile boolean stopFlag = false;
    private volatile AudioTrack track;
    private OfflineTts tts;
    private String ttsVoice;
    private final Object lock = new Object();
    // مسار صوت نظام الهاتف (1.3): Android TextToSpeech للعربية فقط — الباب
    // الوحيد لصوت عربي غير kareem دون اتصال (في كتالوج Piper صوت عربي واحد).
    private TextToSpeech sysTts;
    private volatile int sysArState = -1; // ‎-1 لم يُعرف بعد، 0 لا يوجد، 1 يوجد صوت عربي فعلي
    private volatile Voice sysArVoice;
    private volatile int sysPendingCb = -1;
    // السمع الأصلي (1.4، وتركيبة 1.7): معرّف OfflineRecognizer واحد بصيغة
    // sherpa (int8) بلا عامل ويب — Whisper-small هي الأذن الأصلية الأساسية
    // والوحيدة كما في 1.4/1.5 (أُزيلت أذن 1.6 التجريبية في 1.7 بحكم Hilal
    // التجريبي على هاتفه: فضّل small في الاستعمال الحقيقي). اللغة تُفرض
    // لكل طلب عبر setConfig (يقرأها فكّاك whisper من إعداداته عند كل فكّ
    // ويعيد كتابة رمز اللغة الابتدائي)، فلا إعادة بناء عند تبديل اللغات.
    private OfflineRecognizer asr;
    private File asrEnc, asrDec, asrTokens;
    private String asrLang; // لغة الإعداد الحالي لمعرّف small
    private final Object asrLock = new Object();
    private volatile int asrState = 0; // small: 0 لم يُبنَ بعد، 1 جاهز، ‎-1 فشل نهائي
    private volatile String asrLastKind = ""; // الأذن التي خدمت آخر طلب فعلًا: small

    @JavascriptInterface public void copyText(final String text) {
      runOnUiThread(() -> {
        ClipboardManager cm = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        if (cm != null) {
          cm.setPrimaryClip(ClipData.newPlainText("voice", text));
          Toast.makeText(MainActivity.this, "تم النسخ", Toast.LENGTH_SHORT).show();
        }
      });
    }

    @JavascriptInterface public void stopSpeak() {
      stopFlag = true;
      AudioTrack t = track;
      if (t != null) {
        try { t.pause(); t.flush(); } catch (Exception ignored) {}
      }
      // إيقاف مسار نظام الهاتف أيضًا وإكمال ندائه المعلّق كإيقاف
      if (sysTts != null) { try { sysTts.stop(); } catch (Throwable ignored) {} }
      final int scb = sysPendingCb;
      sysPendingCb = -1;
      if (scb >= 0) runOnUiThread(() -> evalTtsCallback(scb, false, "stopped"));
    }

    // يعمل على خيط الجسر — الحظر مقبول: التوليد والتشغيل ثم ردّ النداء للصفحة
    @JavascriptInterface public void speak(final String text, final String voice, final float speed, final int cbId) {
      // مسار صوت نظام الهاتف (1.3): اختيار ar-system يُروَّت لمحرك الهاتف لا sherpa
      if ("ar-system".equals(voice)) { speakSystem(text, speed, cbId); return; }
      boolean ok = false;
      String err = "";
      synchronized (lock) {
        try {
          stopFlag = false;
          ensureTts(voice);
          GeneratedAudio audio = tts.generate(text, 0, speed);
          float[] samples = audio.getSamples();
          int sr = audio.getSampleRate();
          if (samples != null && samples.length > 0) {
            playSamples(samples, sr);
            ok = true;
          } else {
            err = "empty audio";
          }
        } catch (Throwable e) {
          err = String.valueOf(e);
          Log.e(TAG, "speak failed", e instanceof Exception ? (Exception) e : new Exception(e));
        }
      }
      final boolean fok = ok;
      final String ferr = err;
      runOnUiThread(() -> evalTtsCallback(cbId, fok, ferr, voice));
    }

    /* ===== مسار صوت نظام الهاتف (1.3) — TextToSpeech للعربية فقط =====
       يُهيَّأ من onCreate على الخيط الرئيسي. شرط الظهور في الواجهة: صوت عربي
       فعلي على الجهاز لا يحتاج شبكة (التطبيق بلا إذن إنترنت أصلًا)؛ عند غيابه
       يبقى sysArState=0 ولا يعرض الجسر الخيار للصفحة أبدًا. */

    void ensureSysTts() {
      if (sysTts != null) return;
      try {
        sysTts = new TextToSpeech(MainActivity.this, new TextToSpeech.OnInitListener() {
          @Override public void onInit(int status) {
            if (status == TextToSpeech.SUCCESS) {
              try {
                sysTts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                  @Override public void onStart(String uid) {}
                  @Override public void onDone(String uid) { finishSysUtterance(uid, true, ""); }
                  @Override public void onError(String uid) { finishSysUtterance(uid, false, "system tts error"); }
                });
                Voice v = findArabicVoice(sysTts);
                sysArVoice = v;
                boolean has = v != null;
                if (!has) {
                  try { has = sysTts.isLanguageAvailable(new Locale("ar")) >= TextToSpeech.LANG_AVAILABLE; }
                  catch (Throwable ignored) {}
                }
                sysArState = has ? 1 : 0;
                Log.i(TAG, "system tts ready arabic=" + has + " voice=" + (v != null ? v.getName() : "none"));
              } catch (Throwable e) {
                sysArState = 0;
                Log.e(TAG, "system tts scan failed", e);
              }
            } else {
              sysArState = 0;
              Log.e(TAG, "system tts init failed status=" + status);
            }
            runOnUiThread(() -> {
              try { w.evaluateJavascript("window.__sysTtsReady && window.__sysTtsReady()", null); }
              catch (Throwable ignored) {}
            });
          }
        });
      } catch (Throwable e) {
        sysArState = 0;
        Log.e(TAG, "system tts create failed", e);
      }
    }

    private static Voice findArabicVoice(TextToSpeech t) {
      try {
        java.util.Set<Voice> voices = t.getVoices();
        if (voices != null) {
          for (Voice v : voices) {
            try {
              if (v != null && v.getLocale() != null
                  && "ar".equals(v.getLocale().getLanguage())
                  && !v.isNetworkConnectionRequired()) return v;
            } catch (Throwable ignored) {}
          }
        }
      } catch (Throwable ignored) {}
      return null;
    }

    // للصفحة: هل يوجد صوت عربي فعلي في نظام الهاتف؟ (لا يُعرض ar-system إلا عند true)
    @JavascriptInterface public boolean arabicSystemVoiceAvailable() {
      return sysArState == 1;
    }

    // نطق عبر نظام الهاتف: سرعة المنزلق نفسها إلى setSpeechRate، والإكمال غير
    // متزامن عبر مستمع النطق — يُردّ النداء للصفحة عند انتهاء الجملة فعلًا،
    // فيعمل طابور النطق المتدفق (1.3) على هذا المسار كما على sherpa.
    private void speakSystem(final String text, final float speed, final int cbId) {
      runOnUiThread(() -> {
        try {
          if (sysTts == null || sysArState != 1) { evalTtsCallback(cbId, false, "system voice unavailable"); return; }
          stopFlag = false;
          if (sysArVoice != null) {
            sysTts.setVoice(sysArVoice);
          } else {
            int r = sysTts.setLanguage(new Locale("ar"));
            if (r == TextToSpeech.LANG_MISSING_DATA || r == TextToSpeech.LANG_NOT_SUPPORTED) {
              evalTtsCallback(cbId, false, "arabic system data missing");
              return;
            }
          }
          sysTts.setSpeechRate(speed);
          sysPendingCb = cbId;
          String uid = String.valueOf(cbId);
          Bundle params = new Bundle();
          params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, uid);
          int rc = sysTts.speak(text, TextToSpeech.QUEUE_FLUSH, params, uid);
          if (rc != TextToSpeech.SUCCESS) {
            sysPendingCb = -1;
            evalTtsCallback(cbId, false, "system speak failed");
          }
        } catch (Throwable e) {
          sysPendingCb = -1;
          Log.e(TAG, "system speak failed", e);
          evalTtsCallback(cbId, false, String.valueOf(e));
        }
      });
    }

    private void finishSysUtterance(String uid, boolean ok, String err) {
      int cb;
      try { cb = Integer.parseInt(uid); } catch (Throwable e) { return; }
      if (sysPendingCb != cb) return; // نداء قديم أو أُكمل بالإيقاف — تجاهل
      sysPendingCb = -1;
      final int fcb = cb;
      runOnUiThread(() -> evalTtsCallback(fcb, ok, err, "ar-system"));
    }

    void shutdownSysTts() {
      if (sysTts != null) {
        try { sysTts.stop(); sysTts.shutdown(); } catch (Throwable ignored) {}
        sysTts = null;
      }
    }

    /* ===== السمع الأصلي (1.4) — تركيبة 1.7 =====
       الصفحة ترسل PCM 16kHz (PCM16 بـBase64) من مسار التسجيل القائم نفسه،
       فيتعرّف عليه المعرّف الأصلي هنا. سلسلة السقوط كما في 1.4/1.5:
       Whisper-small أصليًا أولًا، فإن فشل بناؤه أو فكّه ردّ النداء خطأً
       للصفحة فتسقط تلقائيًا إلى عامل الويب القديم الذي يبقى في الحزمة كما
       هو — لا تعطّل كامل أبدًا. فشل البناء نهائي ويُعلَّم (state=-1) فلا
       تُفضَّل الأذن بعده، وسطر السجل يوثّق المسار الخادم لكل طلب.
       (أُزيلت أذن 1.6 التجريبية من هذه التركيبة كليًا — ملفات وجسرًا —
       بحكم Hilal بعد تجربته على هاتفه: 1.4 بأذنها small أفضل عنده.) */

    // تسخين عند إقلاع التطبيق (خيط خلفي من onCreate): بناء أذن small
    // الأصلية كي تكون جاهزة عند أول تسجيل.
    void warmAsr() {
      synchronized (asrLock) {
        try { ensureAsrLocked(); }
        catch (Throwable e) { Log.e(TAG, "asr small warm failed", e); }
      }
    }

    // للصفحة: هل توجد أذن أصلية جاهزة؟ (تُفضّلها الصفحة وتسقط للويب عند غيابها)
    @JavascriptInterface public boolean asrNativeAvailable() {
      return asrState == 1;
    }

    // للصفحة (شارة 1.6 الصادقة، بتركيبة 1.7): اسم الأذن الأصلية الجاهزة
    // فعلًا — "small" حين تجهز، وسلسلة فارغة عند غيابها (عامل الويب هو
    // الخادم حينها). شارة حالة السمع في الصفحة تعرض هذا الاسم كما هو،
    // فلا تدّعي أذنًا غير التي تخدم.
    @JavascriptInterface public String asrNativeKind() {
      if (asrState == 1) return "small";
      return "";
    }

    // للصفحة (1.6، بتركيبة 1.7): الأذن التي خدمت آخر طلب سمع فعلًا —
    // توثّقها الصفحة في سطر وحدة التحكم لكل طلب.
    @JavascriptInterface public String asrLastServedKind() {
      return asrLastKind;
    }

    // تعرّف أصلي: يعمل على خيط الجسر ويحظر حتى الاكتمال (نمط speak نفسه)،
    // ثم يردّ النداء للصفحة بالنص أو بالخطأ. سطر السجل يوثّق المسار الخادم.
    @JavascriptInterface public void transcribeNative(final String b64, final String lang, final int cbId) {
      boolean ok = false;
      String payload = "";
      String served = "";
      long t0 = System.currentTimeMillis();
      int sampleCount = 0;
      try {
        byte[] pcm = Base64.decode(b64, Base64.DEFAULT);
        float[] samples = new float[pcm.length / 2];
        for (int i = 0; i < samples.length; i++) {
          int v = (pcm[2 * i] & 0xff) | (pcm[2 * i + 1] << 8);
          samples[i] = ((short) v) / 32768f;
        }
        sampleCount = samples.length;
        synchronized (asrLock) {
          ensureAsrLocked();
          asrLang = applyAsrLang(asr, asrEnc, asrDec, asrTokens, asrLang, lang);
          payload = decodeChunkedLocked(asr, samples);
          served = "small";
        }
        asrLastKind = served;
        ok = true;
      } catch (Throwable e) {
        payload = String.valueOf(e);
        Log.e(TAG, "asr native failed", e instanceof Exception ? (Exception) e : new Exception(e));
      }
      Log.i(TAG, "asr path=" + (served.isEmpty() ? "native-failed" : served)
          + " lang=" + lang + " ok=" + ok + " samples=" + sampleCount
          + " ms=" + (System.currentTimeMillis() - t0));
      final boolean fok = ok;
      final String fpayload = payload;
      runOnUiThread(() -> evalAsrCallback(cbId, fok, fpayload));
    }

    // بناء المعرّف عند الحاجة (داخل asrLock): استخراج موثّق بالحجم إلى جذر
    // جديد asr/v14 ثم بناء الجلسات بلغة ابتدائية (العربية — لغة الطرف أ).
    private void ensureAsrLocked() throws Exception {
      if (asr != null) return;
      if (asrState == -1) throw new Exception("native asr unavailable (earlier failure)");
      File dir = new File(new File(getFilesDir(), "asr"), "v14/whisper-small");
      if (!dir.isDirectory()) dir.mkdirs();
      asrEnc = new File(dir, "small-encoder.int8.onnx");
      asrDec = new File(dir, "small-decoder.int8.onnx");
      asrTokens = new File(dir, "small-tokens.txt");
      try {
        extractVerified("asr/whisper-small/small-encoder.int8.onnx", asrEnc);
        extractVerified("asr/whisper-small/small-decoder.int8.onnx", asrDec);
        extractVerified("asr/whisper-small/small-tokens.txt", asrTokens);
        asr = new OfflineRecognizer(null, buildAsrConfig(asrEnc, asrDec, asrTokens, "ar"));
      } catch (Throwable e) {
        asrState = -1; // فشل نهائي: لا تُفضّل الصفحة هذا المسار بعد الآن
        throw e instanceof Exception ? (Exception) e : new Exception(e);
      }
      asrLang = "ar";
      asrState = 1;
      Log.i(TAG, "asr small built enc=" + asrEnc.length() + " dec=" + asrDec.length());
    }

    // إعداد معرّف whisper لأذن small — بناء الإعداد (1.4).
    // ملاحظة featureDim=80: محرك whisper في sherpa يقرأ n_mels من بيانات
    // النموذج الوصفية نفسها.
    private OfflineRecognizerConfig buildAsrConfig(File enc, File dec, File tokens, String lang) {
      OfflineWhisperModelConfig wcfg = new OfflineWhisperModelConfig();
      wcfg.setEncoder(enc.getAbsolutePath());
      wcfg.setDecoder(dec.getAbsolutePath());
      wcfg.setLanguage(lang);
      wcfg.setTask("transcribe");
      OfflineModelConfig mcfg = new OfflineModelConfig();
      mcfg.setWhisper(wcfg);
      mcfg.setTokens(tokens.getAbsolutePath());
      mcfg.setNumThreads(4);
      mcfg.setDebug(false);
      mcfg.setProvider("cpu");
      FeatureConfig fcfg = new FeatureConfig();
      fcfg.setSampleRate(16000);
      fcfg.setFeatureDim(80);
      OfflineRecognizerConfig rcfg = new OfflineRecognizerConfig();
      rcfg.setFeatConfig(fcfg);
      rcfg.setModelConfig(mcfg);
      rcfg.setDecodingMethod("greedy_search");
      return rcfg;
    }

    // فرض لغة الطلب على معرّف بعينه (داخل asrLock): setConfig تُحدّث إعداد
    // whisper داخل المحرك، وفكّاكه يقرأ اللغة من إعداداته عند كل فكّ —
    // فلا إعادة بناء. تعيد لغة الإعداد الجديدة لتُحفظ في حقل الأذن.
    private String applyAsrLang(OfflineRecognizer rec, File enc, File dec, File tokens, String cur, String lang) {
      if (lang == null || lang.equals(cur)) return cur;
      rec.setConfig(buildAsrConfig(enc, dec, tokens, lang));
      Log.i(TAG, "asr language set to " + lang);
      return lang;
    }

    // فكّ الصوت بمعرّف بعينه (داخل asrLock). حدّ محرك whisper في sherpa:
    // أول ~29.5 ثانية فقط من أي دفقة واحدة — فنقطع التسجيل (سقفه 45 ثانية
    // أصلًا) إلى قطع 25 ثانية متتالية ونفكّ كلًّا وحدها ثم نصل النصوص.
    private String decodeChunkedLocked(OfflineRecognizer rec, float[] samples) throws Exception {
      final int CHUNK = 25 * 16000;
      StringBuilder out = new StringBuilder();
      for (int off = 0; off < samples.length; off += CHUNK) {
        int n = Math.min(CHUNK, samples.length - off);
        float[] part = new float[n];
        System.arraycopy(samples, off, part, 0, n);
        OfflineStream stream = rec.createStream();
        try {
          stream.acceptWaveform(part, 16000);
          rec.decode(stream);
          String text = rec.getResult(stream).getText();
          if (text != null) {
            text = text.trim();
            if (!text.isEmpty()) {
              if (out.length() > 0) out.append(' ');
              out.append(text);
            }
          }
        } finally {
          try { stream.release(); } catch (Throwable ignored) {}
        }
      }
      return out.toString();
    }

    private void playSamples(float[] samples, int sr) throws Exception {
      int minBuf = AudioTrack.getMinBufferSize(sr, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT);
      int bufSize = Math.max(minBuf * 2, 8192);
      AudioTrack t = new AudioTrack.Builder()
          .setAudioAttributes(new AudioAttributes.Builder()
              .setUsage(AudioAttributes.USAGE_MEDIA)
              .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
          .setAudioFormat(new AudioFormat.Builder()
              .setSampleRate(sr)
              .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
              .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
          .setBufferSizeInBytes(bufSize)
          .setTransferMode(AudioTrack.MODE_STREAM)
          .build();
      track = t;
      try {
        t.play();
        short[] pcm = new short[4096];
        int i = 0;
        while (i < samples.length) {
          if (stopFlag) break;
          int n = Math.min(pcm.length, samples.length - i);
          for (int j = 0; j < n; j++) {
            float v = samples[i + j];
            if (v > 1f) v = 1f; else if (v < -1f) v = -1f;
            pcm[j] = (short) (v * 32767);
          }
          int written = 0;
          while (written < n && !stopFlag) {
            int wr = t.write(pcm, written, n - written);
            if (wr < 0) throw new Exception("AudioTrack.write=" + wr);
            written += wr;
          }
          i += n;
        }
        if (!stopFlag) {
          long deadline = System.currentTimeMillis() + (samples.length * 1000L / Math.max(1, sr)) + 3000;
          while (!stopFlag && System.currentTimeMillis() < deadline) {
            if (t.getPlaybackHeadPosition() >= samples.length) break;
            Thread.sleep(40);
          }
        }
      } finally {
        try { t.stop(); } catch (Exception ignored) {}
        t.release();
        if (track == t) track = null;
      }
    }

    private void ensureTts(String voice) throws Exception {
      if (tts != null && voice.equals(ttsVoice)) return;
      File base = new File(getFilesDir(), "tts");
      File espeakDir = extractEspeak(MainActivity.this);
      // 1.3 — تقوية مسار الصوت بعد بلاغ «صوت ذكر في الحالتين»:
      // (أ) مجلد استخراج مستقل لكل صوت تحت جذر جديد كليًا (tts/v13/voices/<voiceId>/)
      //     فلا يُعاد استعمال أي ملف استخرجته 1.0–1.2 مهما كانت حالته على الجهاز.
      // (ب) الاستخراج موثّق بالحجم: لا يُقبل ملف إلا بطول أصل الـAPK بايتًا.
      // (ج) حذف مجلد الاستخراج القديم المشترك (tts/voices) مرة واحدة — ذاكرة
      //     أصول خالصة تُعاد من الـAPK عند الحاجة، فحذفها آمن ويحرّر المساحة.
      File legacyDir = new File(base, "voices");
      if (legacyDir.isDirectory()) deleteRecursive(legacyDir);
      File voiceDir = new File(new File(base, "v13/voices"), voice);
      if (!voiceDir.isDirectory()) voiceDir.mkdirs();
      File model = new File(voiceDir, "model.onnx");
      File tokens = new File(voiceDir, "tokens.txt");
      extractVerified("tts/voices/" + voice + ".onnx", model);
      extractVerified("tts/voices/" + voice + ".tokens.txt", tokens);
      if (tts != null) {
        try { tts.release(); } catch (Exception ignored) {}
        tts = null;
        ttsVoice = null;
      }
      OfflineTtsVitsModelConfig vits = new OfflineTtsVitsModelConfig();
      vits.setModel(model.getAbsolutePath());
      vits.setLexicon("");
      vits.setTokens(tokens.getAbsolutePath());
      vits.setDataDir(espeakDir.getAbsolutePath());
      vits.setDictDir("");
      OfflineTtsModelConfig mc = new OfflineTtsModelConfig();
      mc.setVits(vits);
      mc.setNumThreads(2);
      mc.setDebug(false);
      mc.setProvider("cpu");
      OfflineTtsConfig cfg = new OfflineTtsConfig();
      cfg.setModel(mc);
      cfg.setRuleFsts("");
      cfg.setRuleFars("");
      cfg.setMaxNumSentences(1);
      // AssetManager=null + مسارات ملفات مطلقة → sherpa يقرأ من نظام الملفات (newFromFile)
      tts = new OfflineTts(null, cfg);
      ttsVoice = voice;
      Log.i(TAG, "tts built voice=" + voice + " model=" + model.getAbsolutePath() + " bytes=" + model.length());
    }

    // استخراج موثّق بالحجم (1.3): يُقبل الملف المستخرج فقط إن طابق طولُه طولَ
    // الأصل داخل الـAPK بايتًا (الأصول مخزّنة دون ضغط فيعمل openFd)؛ عند الاختلاف
    // يُحذف ويُعاد نسخه مرة واحدة، فإن بقي الاختلاف رُفع خطأ مرئي بدل نطقٍ صامت
    // بنموذج غير موثّق. إن تعذّر openFd سقطنا إلى فحص الوجود كما في 1.0–1.2.
    private void extractVerified(String assetPath, File dest) throws Exception {
      long expected = -1;
      try {
        android.content.res.AssetFileDescriptor afd = getAssets().openFd(assetPath);
        expected = afd.getLength();
        afd.close();
      } catch (Throwable ignored) {}
      for (int attempt = 0; attempt < 2; attempt++) {
        if (dest.exists() && (expected < 0 || dest.length() == expected)) return;
        if (dest.exists()) dest.delete();
        copyAsset(MainActivity.this, assetPath, dest);
      }
      if (expected >= 0 && dest.length() != expected) {
        throw new Exception("asset size mismatch: " + assetPath + " got=" + dest.length() + " want=" + expected);
      }
    }

    private static void deleteRecursive(File f) {
      if (f.isDirectory()) {
        File[] kids = f.listFiles();
        if (kids != null) for (File k : kids) deleteRecursive(k);
      }
      try { f.delete(); } catch (Exception ignored) {}
    }

    static File extractEspeak(Activity act) throws Exception {
      File base = new File(act.getFilesDir(), "tts");
      File dir = new File(base, "espeak-ng-data");
      File sentinel = new File(base, "espeak.done");
      if (sentinel.exists() && dir.isDirectory()) return dir;
      extractAssetDir(act, "tts/espeak-ng-data", dir);
      new FileOutputStream(sentinel).close();
      return dir;
    }

    static void extractAssetDir(Activity act, String assetPath, File destDir) throws Exception {
      String[] list = act.getAssets().list(assetPath);
      if (list == null) throw new Exception("missing asset dir: " + assetPath);
      if (!destDir.isDirectory()) destDir.mkdirs();
      for (String name : list) {
        String child = assetPath + "/" + name;
        File out = new File(destDir, name);
        String[] sub = act.getAssets().list(child);
        if (sub != null && sub.length > 0) {
          extractAssetDir(act, child, out);
        } else if (!out.exists()) {
          copyAsset(act, child, out);
        }
      }
    }

    static void copyAsset(Activity act, String assetPath, File dest) throws Exception {
      File parent = dest.getParentFile();
      if (parent != null && !parent.isDirectory()) parent.mkdirs();
      File tmp = new File(dest.getAbsolutePath() + ".tmp");
      try (InputStream in = act.getAssets().open(assetPath);
           FileOutputStream out = new FileOutputStream(tmp)) {
        byte[] buf = new byte[1 << 16];
        int n;
        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
      }
      if (!tmp.renameTo(dest)) throw new Exception("rename failed: " + dest);
    }
  }
}
