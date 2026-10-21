package com.example.vo_hoang_phuc_0118_nhom01;

import android.content.Intent;
import android.net.Uri;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterFragmentActivity {
    private static final String CHANNEL = "nhom01/launcher";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("openUrl".equals(call.method)) {
                        String url = call.argument("url");
                        if (url == null || url.isEmpty()) {
                            result.error("INVALID_URL", "URL is empty", null);
                            return;
                        }
                        try {
                            Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                            startActivity(intent);
                            result.success(true);
                        } catch (Exception e) {
                            result.error("LAUNCH_ERROR", e.getMessage(), null);
                        }
                    } else {
                        result.notImplemented();
                    }
                });
    }
}
