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
import com.k2fsa.sherpa.onnx.GeneratedAudio;
import com.k2fsa.sherpa.onnx.OfflineTts;
import com.k2fsa.sherpa.onnx.OfflineTtsConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
import org.json.JSONObject;

public class MainActivity extends Activity {
  private WebView w;
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
    w.addJavascriptInterface(new VoiceBridge(), "VoiceBridge");
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
    String js = "window.__ttsCallback && window.__ttsCallback(" + id + "," + ok + ","
        + JSONObject.quote(err == null ? "" : err) + ")";
    w.evaluateJavascript(js, null);
  }

  @Override public void onBackPressed() {
    if (w != null && w.canGoBack()) w.goBack(); else super.onBackPressed();
  }

  /* ================= جسر النطق والنسخ ================= */
  public class VoiceBridge {
    private volatile boolean stopFlag = false;
    private volatile AudioTrack track;
    private OfflineTts tts;
    private String ttsVoice;
    private final Object lock = new Object();

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
    }

    // يعمل على خيط الجسر — الحظر مقبول: التوليد والتشغيل ثم ردّ النداء للصفحة
    @JavascriptInterface public void speak(final String text, final String voice, final float speed, final int cbId) {
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
      runOnUiThread(() -> evalTtsCallback(cbId, fok, ferr));
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
