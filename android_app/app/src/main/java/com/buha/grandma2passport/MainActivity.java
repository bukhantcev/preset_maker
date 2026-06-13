package com.buha.grandma2passport;

import android.Manifest;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;
import android.graphics.pdf.PdfDocument;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.DocumentsContract;
import android.os.Environment;
import android.provider.Settings;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.Size;
import android.view.DragEvent;
import android.view.Gravity;
import android.view.Surface;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.MimeTypeMap;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.ArrayAdapter;
import android.widget.AdapterView;
import android.widget.Toast;

import androidx.activity.ComponentActivity;
import androidx.annotation.NonNull;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageCapture;
import androidx.camera.core.ImageCaptureException;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;

import com.google.common.util.concurrent.ListenableFuture;
import com.jcraft.jsch.ChannelSftp;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.Session;
import com.jcraft.jsch.SftpATTRS;
import com.jcraft.jsch.SftpException;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.Comparator;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import java.util.Vector;

import javax.xml.parsers.DocumentBuilderFactory;

public class MainActivity extends ComponentActivity {
    private static final int REQ_XML = 10;
    private static final int REQ_PROJECT_XML = 11;
    private static final int REQ_CAMERA_PERMISSION = 12;
    private static final int REQ_IMPORT_PHOTO = 13;
    private static final int REQ_PARTITURA_XML = 14;
    private static final int BRAND_BLACK = 0xff000000;
    private static final int BRAND_PANEL = 0xff151515;
    private static final int BRAND_PANEL_ALT = 0xff202020;
    private static final int BRAND_YELLOW = 0xffffb800;
    private static final int BRAND_YELLOW_SOFT = 0xffffd35a;
    private static final int BRAND_YELLOW_DARK = 0xff8a6500;
    private static final int BRAND_SILVER = 0xffd4d4d4;
    private static final int BRAND_SILVER_SOFT = 0xffffffff;
    private static final int BRAND_SILVER_DARK = 0xff777777;
    private static final int BRAND_TEXT = 0xfff4f4f4;
    private static final int BRAND_MUTED = 0xffb8b8b8;
    private static final int BRAND_SELECTED = 0xffffc21a;
    private static final int BRAND_GREEN = 0xff4ee06d;
    private static final int BRAND_RED = 0xffff4545;
    private static final String REMOTE_ROOT_NAME = "MA2_passports";

    private final ArrayList<PresetItem> items = new ArrayList<>();
    private final ArrayList<PassportRow> rows = new ArrayList<>();
    private final ArrayList<String> listLabels = new ArrayList<>();
    private ArrayAdapter<String> adapter;

    private TextView summaryText;
    private TextView currentText;
    private EditText descriptionEdit;
    private PreviewView cameraPreview;
    private ImageView capturedPreview;
    private ListView listView;
    private Spinner cameraSpinner;
    private Button startButton;
    private Button photoButton;
    private Button useButton;
    private Button retakeButton;
    private Button skipButton;
    private Button deleteButton;
    private Button prevButton;
    private Button nextButton;
    private Button addButton;
    private Button importPhotoButton;
    private TextView emptyPhotoText;
    private Button deletePhotoButton;
    private LinearLayout emptyPhotoBox;

    private File projectDir;
    private File photosDir;
    private File filesScreenProjectDir;
    private String filesScreenKind = "presets";
    private String projectListMode = "presets";
    private boolean projectBrowserCloud = false;
    private File projectModeDir;
    private boolean projectModeCloud = false;
    private File selectedPartituraProjectDir;
    private final ArrayList<PartituraField> partituraFields = new ArrayList<>();
    private File tempPhoto;
    private int tempPhotoIndex = -1;
    private ImageCapture imageCapture;
    private Camera boundCamera;
    private ExecutorService cameraExecutor;
    private String showTitle = "show";
    private int index = 0;
    private int draggedPartituraFieldIndex = -1;
    private boolean running = false;
    private boolean loadingDescription = false;
    private boolean takingPhoto = false;
    private boolean cameraScreen = false;
    private String currentScreen = "start";
    private int lensFacing = CameraSelector.LENS_FACING_BACK;
    private final Object passportWriteLock = new Object();
    private boolean remoteMode = false;
    private boolean remoteConnected = false;
    private String cloudProvider = "sftp";
    private String cloudUrl = "";
    private int cloudPort = 22;
    private String cloudUser = "";
    private String cloudPassword = "";
    private String yandexAccessToken = "";
    private String yandexRefreshToken = "";
    private String remoteBasePath = "";
    private TextView loadingText;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        cameraExecutor = Executors.newSingleThreadExecutor();
        try {
            passportsRootDir();
        } catch (Exception ignored) {
        }
        loadServerSettings();
        showStartScreen();
        tryConnectRemoteOnStart();
    }

    @Override
    public void setContentView(View view) {
        if (view != null) {
            view.setBackgroundColor(BRAND_BLACK);
            applyBrandStyle(view);
        }
        super.setContentView(view);
    }

    private void applyBrandStyle(View view) {
        if (view instanceof CheckBox) {
            styleCheckBox((CheckBox) view);
        } else if (view instanceof Button) {
            styleButton((Button) view);
        } else if (view instanceof EditText) {
            styleEditText((EditText) view);
        } else if (view instanceof Spinner) {
            styleSpinner((Spinner) view);
        } else if (view instanceof TextView) {
            TextView text = (TextView) view;
            int current = text.getCurrentTextColor();
            if (current != BRAND_YELLOW
                    && current != BRAND_YELLOW_SOFT
                    && current != BRAND_MUTED
                    && current != BRAND_SILVER
                    && current != BRAND_SILVER_DARK) {
                text.setTextColor(BRAND_TEXT);
            }
            text.setIncludeFontPadding(true);
        } else if (view instanceof ListView) {
            ListView list = (ListView) view;
            list.setBackgroundColor(BRAND_BLACK);
            list.setCacheColorHint(BRAND_BLACK);
            list.setDividerHeight(dp(2));
            list.setDivider(null);
        }

        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                applyBrandStyle(group.getChildAt(i));
            }
        }
    }

    private void styleButton(Button button) {
        CharSequence text = button.getText();
        CharSequence description = button.getContentDescription();
        boolean emptyText = text == null || text.length() == 0;
        boolean photoButton = description != null && "Фото".contentEquals(description);
        if (emptyText && photoButton) return;
        if ("×".contentEquals(text)) return;
        if (button == deletePhotoButton && "Удалить".contentEquals(text)) return;
        boolean service = isServiceButtonText(text);
        int accent = service ? BRAND_SILVER : BRAND_YELLOW;
        int accentSoft = service ? BRAND_SILVER_SOFT : BRAND_YELLOW_SOFT;
        int accentDark = service ? BRAND_SILVER_DARK : BRAND_YELLOW_DARK;
        button.setAllCaps(false);
        button.setTextColor(new ColorStateList(
                new int[][]{new int[]{-android.R.attr.state_enabled}, new int[]{android.R.attr.state_pressed}, new int[]{}},
                new int[]{accentDark, BRAND_BLACK, accent}
        ));
        button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        button.setMinHeight(dp(48));
        button.setPadding(dp(14), dp(8), dp(14), dp(8));
        button.setBackground(buttonBackground(accent, accentSoft, accentDark));
        ViewGroup.LayoutParams lp = button.getLayoutParams();
        if (lp instanceof LinearLayout.LayoutParams) {
            LinearLayout.LayoutParams params = (LinearLayout.LayoutParams) lp;
            int gap = dp(5);
            params.setMargins(
                    Math.max(params.leftMargin, gap),
                    Math.max(params.topMargin, gap),
                    Math.max(params.rightMargin, gap),
                    Math.max(params.bottomMargin, gap)
            );
            button.setLayoutParams(params);
        }
    }

    private boolean isServiceButtonText(CharSequence text) {
        if (text == null) return false;
        String value = text.toString();
        return value.equals("Назад")
                || value.equals("Открыть XML")
                || value.equals("Настройка облака")
                || value.equals("Открыть")
                || value.equals("Открыть пресеты")
                || value.equals("Открыть партитуру")
                || value.equals("Переименовать")
                || value.equals("Загрузить на устройство")
                || value.equals("Экспорт")
                || value.equals("Удалить выбранное")
                || value.equals("Удалить")
                || value.equals("Пропустить");
    }

    private StateListDrawable buttonBackground(int accent, int accentSoft, int accentDark) {
        StateListDrawable states = new StateListDrawable();
        states.addState(new int[]{-android.R.attr.state_enabled}, rounded(BRAND_BLACK, accentDark, dp(1), dp(8)));
        states.addState(new int[]{android.R.attr.state_pressed}, rounded(accent, accent, dp(2), dp(8)));
        states.addState(new int[]{android.R.attr.state_focused}, rounded(BRAND_PANEL, accentSoft, dp(2), dp(8)));
        states.addState(new int[]{}, rounded(BRAND_BLACK, accent, dp(2), dp(8)));
        return states;
    }

    private GradientDrawable rounded(int fill, int stroke, int strokeWidth, int radius) {
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(fill);
        bg.setCornerRadius(radius);
        bg.setStroke(strokeWidth, stroke);
        return bg;
    }

    private void styleEditText(EditText edit) {
        edit.setTextColor(BRAND_TEXT);
        edit.setHintTextColor(BRAND_MUTED);
        edit.setBackground(rounded(BRAND_PANEL, BRAND_YELLOW_DARK, dp(1), dp(6)));
        edit.setPadding(dp(12), dp(8), dp(12), dp(8));
    }

    private void styleCheckBox(CheckBox check) {
        check.setTextColor(check.isChecked() ? BRAND_YELLOW : BRAND_SILVER);
        check.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        check.setBackgroundColor(Color.TRANSPARENT);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            check.setButtonTintList(new ColorStateList(
                    new int[][]{new int[]{android.R.attr.state_checked}, new int[]{}},
                    new int[]{BRAND_YELLOW, BRAND_MUTED}
            ));
        }
    }

    private void styleSpinner(Spinner spinner) {
        spinner.setBackground(rounded(BRAND_BLACK, BRAND_SILVER, dp(2), dp(8)));
        spinner.setPadding(dp(10), 0, dp(10), 0);
    }

    private void showStartScreen() {
        currentScreen = "start";
        cameraScreen = false;
        filesScreenProjectDir = null;
        projectModeDir = null;
        stopCamera();

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setPadding(36, 36, 36, 36);

        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.logo_pc);
        logo.setAdjustViewBounds(true);
        logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
        LinearLayout.LayoutParams logoParams = new LinearLayout.LayoutParams(-1, dp(340));
        logoParams.setMargins(0, 0, 0, dp(28));
        root.addView(logo, logoParams);

        Button projectsButton = new Button(this);
        projectsButton.setText("Проекты");
        projectsButton.setOnClickListener(v -> showProjectSourceScreen());
        LinearLayout.LayoutParams projectsParams = new LinearLayout.LayoutParams(-1, -2);
        projectsParams.setMargins(0, dp(8), 0, dp(8));
        root.addView(projectsButton, projectsParams);

        Button cloudButton = new Button(this);
        cloudButton.setText(remoteConnected ? "Облако подключено" : "Настройки облака");
        cloudButton.setOnClickListener(v -> showSftpSettingsDialog());
        LinearLayout.LayoutParams cloudParams = new LinearLayout.LayoutParams(-1, -2);
        cloudParams.setMargins(0, dp(8), 0, dp(8));
        root.addView(cloudButton, cloudParams);

        addSpacer(root, 1);

        setContentView(root);
    }

    private void showProjectSourceScreen() {
        currentScreen = "project_source";
        cameraScreen = false;
        filesScreenProjectDir = null;
        projectModeDir = null;
        stopCamera();

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(24), dp(24), dp(24), dp(24));

        TextView title = new TextView(this);
        title.setText("Проекты");
        title.setTextSize(24);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setGravity(Gravity.CENTER);
        root.addView(title, new LinearLayout.LayoutParams(-1, -2));

        addSpacer(root, 1);

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.VERTICAL);
        buttons.setMinimumWidth(dp(560));

        Button local = new Button(this);
        local.setText("Устройство");
        local.setOnClickListener(v -> {
            projectBrowserCloud = false;
            remoteMode = false;
            saveServerSettings();
            showProjectListScreen("projects");
        });
        buttons.addView(local, new LinearLayout.LayoutParams(-1, dp(76)));

        Button cloud = new Button(this);
        cloud.setText("Облако");
        cloud.setOnClickListener(v -> {
            projectBrowserCloud = true;
            remoteMode = true;
            saveServerSettings();
            showProjectListScreen("projects");
        });
        LinearLayout.LayoutParams cloudParams = new LinearLayout.LayoutParams(-1, -2);
        cloudParams.setMargins(0, dp(14), 0, 0);
        buttons.addView(cloud, cloudParams);

        TextView status = new TextView(this);
        status.setText(remoteConnected ? "✓ облако подключено" : "облако подключится при открытии");
        status.setTextColor(remoteConnected ? BRAND_GREEN : BRAND_MUTED);
        status.setGravity(Gravity.CENTER);
        status.setPadding(0, dp(18), 0, 0);
        buttons.addView(status, new LinearLayout.LayoutParams(-1, -2));
        root.addView(buttons, new LinearLayout.LayoutParams(-1, -2));

        addSpacer(root, 1);

        Button back = new Button(this);
        back.setText("Назад");
        back.setOnClickListener(v -> showStartScreen());
        root.addView(back, new LinearLayout.LayoutParams(-1, -2));

        setContentView(root);
    }

    private View storagePanel() {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(14), dp(14), dp(14), dp(14));
        panel.setBackground(rounded(BRAND_PANEL, BRAND_YELLOW, dp(1), dp(10)));

        TextView title = new TextView(this);
        title.setText("Хранилище");
        title.setTextSize(15);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setTextColor(BRAND_SILVER);
        panel.addView(title, new LinearLayout.LayoutParams(-1, -2));

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        Button local = new Button(this);
        local.setText("Локально");
        local.setTextColor(remoteMode ? BRAND_SILVER : BRAND_YELLOW);
        local.setBackground(rounded(BRAND_BLACK, remoteMode ? BRAND_SILVER_DARK : BRAND_YELLOW, dp(2), dp(8)));
        local.setOnClickListener(v -> {
            remoteMode = false;
            saveServerSettings();
            showStartScreen();
        });
        row.addView(local, buttonParams());

        Button remote = new Button(this);
        remote.setText("Облако");
        remote.setTextColor(remoteMode ? BRAND_YELLOW : BRAND_SILVER);
        remote.setBackground(rounded(BRAND_BLACK, remoteMode ? BRAND_YELLOW : BRAND_SILVER_DARK, dp(2), dp(8)));
        remote.setOnClickListener(v -> {
            remoteMode = true;
            saveServerSettings();
            showStartScreen();
        });
        row.addView(remote, buttonParams());
        panel.addView(row, new LinearLayout.LayoutParams(-1, -2));

        TextView status = new TextView(this);
        String providerTitle = "yandex_disk".equals(cloudProvider) ? "Яндекс.Диск" : "SFTP";
        status.setText(remoteMode ? (remoteConnected ? "✓ " + providerTitle + " подключено" : "✕ нет подключения") : "Локально: Документы/MA2_passports");
        status.setTextColor(remoteMode ? (remoteConnected ? BRAND_GREEN : BRAND_RED) : BRAND_SILVER);
        status.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        status.setPadding(0, dp(6), 0, 0);
        panel.addView(status, new LinearLayout.LayoutParams(-1, -2));

        if (remoteMode) {
            Button settings = new Button(this);
            settings.setText("Настройка облака");
            settings.setOnClickListener(v -> showSftpSettingsDialog());
            panel.addView(settings, new LinearLayout.LayoutParams(-1, -2));
        }
        return panel;
    }

    private void showPresetSetupScreen() {
        currentScreen = "preset_setup";
        cameraScreen = false;
        filesScreenProjectDir = null;
        stopCamera();

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 24);

        TextView cameraLabel = new TextView(this);
        cameraLabel.setText("Камера");
        cameraLabel.setTextColor(BRAND_SILVER);
        cameraLabel.setPadding(0, 0, 0, 8);
        root.addView(cameraLabel);

        cameraSpinner = new Spinner(this);
        ArrayAdapter<String> cameraAdapter = new ArrayAdapter<>(this, android.R.layout.simple_spinner_item, new String[]{"Задняя камера", "Передняя камера"});
        cameraAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        cameraSpinner.setAdapter(cameraAdapter);
        cameraSpinner.setSelection(lensFacing == CameraSelector.LENS_FACING_FRONT ? 1 : 0);
        root.addView(cameraSpinner, new LinearLayout.LayoutParams(-1, -2));

        TextView filesLabel = new TextView(this);
        filesLabel.setText("Проект");
        filesLabel.setPadding(0, dp(28), 0, 8);
        root.addView(filesLabel);

        Button openButton = new Button(this);
        openButton.setText("Загрузить XML");
        openButton.setOnClickListener(v -> {
            lensFacing = cameraSpinner.getSelectedItemPosition() == 1 ? CameraSelector.LENS_FACING_FRONT : CameraSelector.LENS_FACING_BACK;
            openXml();
        });
        root.addView(openButton, new LinearLayout.LayoutParams(-1, -2));

        Button openProjectButton = new Button(this);
        openProjectButton.setText("Открыть проект");
        openProjectButton.setOnClickListener(v -> {
            lensFacing = cameraSpinner.getSelectedItemPosition() == 1 ? CameraSelector.LENS_FACING_FRONT : CameraSelector.LENS_FACING_BACK;
            showProjectListScreen("presets");
        });
        root.addView(openProjectButton, new LinearLayout.LayoutParams(-1, -2));

        addSpacer(root, 1);

        Button backButton = new Button(this);
        backButton.setText("Назад");
        backButton.setOnClickListener(v -> showStartScreen());
        root.addView(backButton, new LinearLayout.LayoutParams(-1, -2));

        setContentView(root);
    }

    private void addSpacer(LinearLayout root, int weight) {
        TextView spacer = new TextView(this);
        root.addView(spacer, new LinearLayout.LayoutParams(-1, 0, weight));
    }

    private void showLoadingScreen(String message) {
        currentScreen = "loading";
        cameraScreen = false;
        stopCamera();
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setPadding(36, 36, 36, 36);

        TextView text = new TextView(this);
        loadingText = text;
        text.setText(message);
        text.setTextSize(22);
        text.setGravity(Gravity.CENTER);
        text.setTextColor(BRAND_YELLOW);
        text.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(text, new LinearLayout.LayoutParams(-1, -2));
        setContentView(root);
    }

    private void updateLoading(String message) {
        runOnUiThread(() -> {
            if (loadingText != null) loadingText.setText(message);
        });
    }

    private void showPartituraSetupScreen() {
        currentScreen = "partitura_setup";
        cameraScreen = false;
        filesScreenProjectDir = null;
        stopCamera();
        ensurePartituraFields();

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 24);

        TextView title = new TextView(this);
        title.setText("Партитура");
        title.setTextSize(22);
        root.addView(title, new LinearLayout.LayoutParams(-1, -2));

        ArrayList<File> projects = projectDirs();
        if (selectedPartituraProjectDir == null && !projects.isEmpty()) selectedPartituraProjectDir = projects.get(0);

        boolean openedFromProject = selectedPartituraProjectDir != null && projectModeDir != null
                && selectedPartituraProjectDir.getAbsolutePath().equals(projectModeDir.getAbsolutePath());
        if (!openedFromProject) {
            Button loadXmlButton = new Button(this);
            loadXmlButton.setText("Загрузить XML");
            loadXmlButton.setOnClickListener(v -> openPartituraXml());
            root.addView(loadXmlButton, new LinearLayout.LayoutParams(-1, -2));

            Button openProjectButton = new Button(this);
            openProjectButton.setText(selectedPartituraProjectDir == null
                    ? "Открыть проект"
                    : "Проект: " + displayTitle(projectTitleFromDir(selectedPartituraProjectDir)));
            openProjectButton.setOnClickListener(v -> showProjectListScreen("partitura"));
            root.addView(openProjectButton, new LinearLayout.LayoutParams(-1, -2));
        } else {
            TextView project = new TextView(this);
            project.setText("Проект: " + displayTitle(projectTitleFromDir(selectedPartituraProjectDir)));
            project.setTextColor(BRAND_SILVER);
            project.setTextSize(18);
            project.setGravity(Gravity.CENTER);
            project.setPadding(0, dp(12), 0, dp(12));
            root.addView(project, new LinearLayout.LayoutParams(-1, -2));
        }

        TextView hint = new TextView(this);
        hint.setText("Включи нужные поля.");
        hint.setPadding(0, dp(14), 0, dp(8));
        root.addView(hint, new LinearLayout.LayoutParams(-1, -2));

        ScrollView scroll = new ScrollView(this);
        LinearLayout fields = new LinearLayout(this);
        fields.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(fields, new ScrollView.LayoutParams(-1, -2));
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        for (int i = 0; i < partituraFields.size(); i++) {
            fields.addView(partituraFieldRow(i));
        }

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        Button createButton = new Button(this);
        createButton.setText("Создать партитуру");
        createButton.setOnClickListener(v -> createPartituraFromSettings());
        actions.addView(createButton, new LinearLayout.LayoutParams(0, -2, 1));
        Button xmlButton = new Button(this);
        xmlButton.setText("XML");
        xmlButton.setOnClickListener(v -> savePartituraShowXmlFromSettings());
        actions.addView(xmlButton, new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(actions, new LinearLayout.LayoutParams(-1, -2));

        Button backButton = new Button(this);
        backButton.setText("Назад");
        backButton.setOnClickListener(v -> {
            if (projectModeDir != null) showProjectModeScreen(projectModeDir, projectModeCloud);
            else showStartScreen();
        });
        root.addView(backButton, new LinearLayout.LayoutParams(-1, -2));

        setContentView(root);
    }

    private View partituraFieldRow(int position) {
        PartituraField field = partituraFields.get(position);
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(dp(12), dp(10), dp(12), dp(10));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(BRAND_PANEL);
        bg.setCornerRadius(dp(8));
        bg.setStroke(dp(1), field.enabled ? BRAND_YELLOW : BRAND_SILVER_DARK);
        row.setBackground(bg);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(0, dp(6), 0, dp(6));
        row.setLayoutParams(params);

        CheckBox check = new CheckBox(this);
        check.setText((position + 1) + ". " + field.title);
        check.setTextColor(field.enabled ? BRAND_YELLOW : BRAND_SILVER);
        check.setTextSize(16);
        check.setChecked(field.enabled);
        check.setOnCheckedChangeListener((buttonView, isChecked) -> {
            field.enabled = isChecked;
            showPartituraSetupScreen();
        });
        row.addView(check, new LinearLayout.LayoutParams(-1, -2));

        View.OnLongClickListener dragStarter = v -> {
            draggedPartituraFieldIndex = position;
            ClipData data = ClipData.newPlainText("partitura_field", field.id);
            View.DragShadowBuilder shadow = new View.DragShadowBuilder(row);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) row.startDragAndDrop(data, shadow, null, 0);
            else row.startDrag(data, shadow, null, 0);
            return true;
        };
        row.setOnLongClickListener(dragStarter);
        check.setOnLongClickListener(dragStarter);
        row.setOnDragListener((v, event) -> {
            if (event.getAction() == DragEvent.ACTION_DROP) {
                movePartituraField(draggedPartituraFieldIndex, position);
                draggedPartituraFieldIndex = -1;
                return true;
            }
            return true;
        });
        return row;
    }

    private void movePartituraField(int from, int to) {
        if (from < 0 || from >= partituraFields.size() || to < 0 || to >= partituraFields.size() || from == to) return;
        PartituraField field = partituraFields.remove(from);
        partituraFields.add(to, field);
        showPartituraSetupScreen();
    }

    private void showMovePartituraFieldMenu(int position) {
        String[] actions = {"Вверх", "Вниз"};
        new AlertDialog.Builder(this)
                .setTitle(partituraFields.get(position).title)
                .setItems(actions, (dialog, which) -> {
                    if (which == 0 && position > 0) {
                        PartituraField field = partituraFields.remove(position);
                        partituraFields.add(position - 1, field);
                        showPartituraSetupScreen();
                    } else if (which == 1 && position + 1 < partituraFields.size()) {
                        PartituraField field = partituraFields.remove(position);
                        partituraFields.add(position + 1, field);
                        showPartituraSetupScreen();
                    }
                })
                .show();
    }

    private void choosePartituraProject(ArrayList<File> projects) {
        if (projects.isEmpty()) {
            Toast.makeText(this, "Нет проектов в Documents/MA2_passports", Toast.LENGTH_LONG).show();
            return;
        }
        String[] names = new String[projects.size()];
        for (int i = 0; i < projects.size(); i++) names[i] = displayTitle(projectTitleFromDir(projects.get(i)));
        new AlertDialog.Builder(this)
                .setTitle("Проект")
                .setItems(names, (dialog, which) -> {
                    selectedPartituraProjectDir = projects.get(which);
                    showPartituraSetupScreen();
                })
                .show();
    }

    private void ensurePartituraFields() {
        if (!partituraFields.isEmpty()) return;
        partituraFields.add(new PartituraField("number", "Номер", true));
        partituraFields.add(new PartituraField("name", "Реплика", true));
        partituraFields.add(new PartituraField("trigger", "Trigger", false));
        partituraFields.add(new PartituraField("trigger_time", "Trigger time", false));
        partituraFields.add(new PartituraField("fade", "Fade", true));
        partituraFields.add(new PartituraField("downfade", "Downfade", false));
        partituraFields.add(new PartituraField("delay", "Delay", false));
        partituraFields.add(new PartituraField("info", "Инфо", true));
        partituraFields.add(new PartituraField("command", "Command", false));
    }

    private ArrayList<File> projectDirs() {
        ArrayList<File> result = new ArrayList<>();
        try {
            File rootDir = passportsRootDir();
            File[] dirs = rootDir.listFiles(file -> file.isDirectory() && findProjectXml(file) != null);
            if (dirs != null) {
                for (File dir : dirs) result.add(dir);
            }
        } catch (Exception ignored) {
        }
        return result;
    }

    private void buildUi() {
        boolean landscape = getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE;
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(landscape ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
        root.setPadding(18, 18, 18, 18);

        LinearLayout left = new LinearLayout(this);
        left.setOrientation(LinearLayout.VERTICAL);
        LinearLayout right = new LinearLayout(this);
        right.setOrientation(LinearLayout.VERTICAL);

        LinearLayout main = landscape ? right : root;

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);

        Button openButton = new Button(this);
        openButton.setText("Открыть XML");
        openButton.setOnClickListener(v -> openXml());
        top.addView(openButton);

        Button partButton = new Button(this);
        partButton.setText("Партитура");
        partButton.setOnClickListener(v -> exportPartitura());
        top.addView(partButton);

        summaryText = new TextView(this);
        summaryText.setText("Выберите XML");
        summaryText.setPadding(16, 0, 0, 0);
        top.addView(summaryText, new LinearLayout.LayoutParams(0, -2, 1));
        main.addView(top);

        currentText = new TextView(this);
        currentText.setTextSize(18);
        currentText.setPadding(0, 16, 0, 8);
        main.addView(currentText);

        descriptionEdit = new EditText(this);
        descriptionEdit.setHint("Описание");
        descriptionEdit.setMinLines(2);
        descriptionEdit.setOnFocusChangeListener((v, hasFocus) -> {
            if (!hasFocus) saveDescription();
        });
        main.addView(descriptionEdit);

        FrameLayout cameraBox = new FrameLayout(this);
        cameraBox.setBackgroundColor(BRAND_PANEL);
        cameraPreview = new PreviewView(this);
        cameraPreview.setScaleType(PreviewView.ScaleType.FILL_CENTER);
        cameraPreview.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        capturedPreview = new ImageView(this);
        capturedPreview.setAdjustViewBounds(true);
        capturedPreview.setScaleType(ImageView.ScaleType.FIT_CENTER);
        capturedPreview.setBackgroundColor(BRAND_PANEL);
        cameraBox.addView(cameraPreview, new FrameLayout.LayoutParams(-1, -1));
        cameraBox.addView(capturedPreview, new FrameLayout.LayoutParams(-1, -1));
        capturedPreview.setVisibility(View.GONE);
        if (landscape) {
            left.addView(cameraBox, new LinearLayout.LayoutParams(-1, 0, 1));
        } else {
            main.addView(cameraBox, new LinearLayout.LayoutParams(-1, 0, 2));
        }

        LinearLayout controlsPanel = new LinearLayout(this);
        controlsPanel.setOrientation(LinearLayout.VERTICAL);
        LinearLayout controls = buttonRow();
        LinearLayout photoActions = buttonRow();

        startButton = new Button(this);
        startButton.setText("Начать");
        startButton.setEnabled(false);
        startButton.setOnClickListener(v -> toggleRun());
        controls.addView(startButton, buttonParams());

        photoButton = new Button(this);
        photoButton.setText("Фото");
        photoButton.setEnabled(false);
        photoButton.setOnClickListener(v -> takePhoto());
        controls.addView(photoButton, buttonParams());

        useButton = new Button(this);
        useButton.setText("Использовать");
        useButton.setVisibility(View.GONE);
        useButton.setOnClickListener(v -> usePhoto());
        photoActions.addView(useButton, buttonParams());

        retakeButton = new Button(this);
        retakeButton.setText("Переснять");
        retakeButton.setVisibility(View.GONE);
        retakeButton.setOnClickListener(v -> takePhoto());
        photoActions.addView(retakeButton, buttonParams());

        skipButton = new Button(this);
        skipButton.setText("Пропустить");
        skipButton.setEnabled(false);
        skipButton.setOnClickListener(v -> skipItem());
        controls.addView(skipButton, buttonParams());

        Button exportButton = new Button(this);
        exportButton.setText("Экспорт");
        exportButton.setOnClickListener(v -> exportPresets(true));
        photoActions.addView(exportButton, buttonParams());

        controlsPanel.addView(controls);
        controlsPanel.addView(photoActions);
        main.addView(controlsPanel);

        LinearLayout rowActions = new LinearLayout(this);
        rowActions.setOrientation(LinearLayout.HORIZONTAL);
        deleteButton = new Button(this);
        deleteButton.setText("Удалить выбранное");
        deleteButton.setOnClickListener(v -> deleteCurrent());
        rowActions.addView(deleteButton);
        main.addView(rowActions);

        listView = new ListView(this);
        adapter = presetListAdapter();
        listView.setAdapter(adapter);
        listView.setOnItemClickListener((parent, view, position, id) -> {
            saveDescription();
            index = position;
            showCurrent();
        });
        main.addView(listView, new LinearLayout.LayoutParams(-1, 0, 2));

        if (landscape) {
            root.addView(left, new LinearLayout.LayoutParams(0, -1, 3));
            root.addView(right, new LinearLayout.LayoutParams(0, -1, 2));
        }

        setContentView(root);
        if (!items.isEmpty()) {
            refreshList();
            showCurrent();
            summaryText.setText("Пресетов/строк: " + items.size());
            startButton.setText(running ? "Стоп" : "Начать");
            startButton.setEnabled(true);
            photoButton.setEnabled(running);
            skipButton.setEnabled(running);
        }
        cameraPreview.post(this::ensureCamera);
    }

    private LinearLayout buttonRow() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        return row;
    }

    private LinearLayout.LayoutParams buttonParams() {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, -2, 1);
        params.setMargins(3, 3, 3, 3);
        return params;
    }

    private ArrayAdapter<String> presetListAdapter() {
        return new ArrayAdapter<String>(this, android.R.layout.simple_list_item_1, listLabels) {
            @NonNull
            @Override
            public View getView(int position, View convertView, @NonNull ViewGroup parent) {
                TextView view = (TextView) super.getView(position, convertView, parent);
                view.setPadding(18, 14, 18, 14);
                if (position == index) {
                    view.setBackgroundColor(BRAND_SELECTED);
                    view.setTextColor(BRAND_BLACK);
                    view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
                } else {
                    view.setBackgroundColor(BRAND_PANEL_ALT);
                    view.setTextColor(BRAND_TEXT);
                    view.setTypeface(Typeface.DEFAULT, Typeface.NORMAL);
                }
                return view;
            }
        };
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private void showPresetWorkspace() {
        currentScreen = "preset_workspace";
        cameraScreen = false;
        filesScreenProjectDir = null;
        stopCamera();

        boolean landscape = getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE;
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(landscape ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
        root.setPadding(14, 14, 14, 14);

        LinearLayout topPane = new LinearLayout(this);
        topPane.setOrientation(LinearLayout.VERTICAL);

        LinearLayout navRow = buttonRow();
        Button back = new Button(this);
        back.setText("Назад");
        back.setOnClickListener(v -> {
            saveDescription();
            savePassportQuietly();
            if (projectModeDir != null) showProjectModeScreen(projectModeDir, projectModeCloud);
            else showProjectListScreen("projects");
        });
        navRow.addView(back, new LinearLayout.LayoutParams(0, -2, 1));
        TextView spacer = new TextView(this);
        navRow.addView(spacer, new LinearLayout.LayoutParams(0, -2, 2));
        topPane.addView(navRow, new LinearLayout.LayoutParams(-1, -2));

        currentText = new TextView(this);
        currentText.setTextSize(17);
        topPane.addView(currentText, new LinearLayout.LayoutParams(-1, -2));

        FrameLayout photoBox = new FrameLayout(this);
        photoBox.setBackgroundColor(BRAND_PANEL);

        capturedPreview = new ImageView(this);
        capturedPreview.setAdjustViewBounds(true);
        capturedPreview.setScaleType(ImageView.ScaleType.FIT_CENTER);
        capturedPreview.setOnClickListener(v -> openCameraFromCurrent());
        photoBox.addView(capturedPreview, new FrameLayout.LayoutParams(-1, -1));

        emptyPhotoBox = new LinearLayout(this);
        emptyPhotoBox.setOrientation(LinearLayout.VERTICAL);
        emptyPhotoBox.setGravity(Gravity.CENTER);
        importPhotoButton = new Button(this);
        importPhotoButton.setText("Загрузить фото");
        importPhotoButton.setOnClickListener(v -> importPhotoForCurrent());
        emptyPhotoBox.addView(importPhotoButton, new LinearLayout.LayoutParams(-2, -2));
        emptyPhotoText = new TextView(this);
        emptyPhotoText.setText("или нажми кнопку Фото внизу");
        emptyPhotoText.setTextColor(BRAND_MUTED);
        emptyPhotoText.setGravity(Gravity.CENTER);
        emptyPhotoBox.addView(emptyPhotoText, new LinearLayout.LayoutParams(-2, -2));
        photoBox.addView(emptyPhotoBox, new FrameLayout.LayoutParams(-1, -1));

        deletePhotoButton = new Button(this);
        deletePhotoButton.setText("Удалить");
        deletePhotoButton.setTextSize(11);
        deletePhotoButton.setTextColor(Color.WHITE);
        GradientDrawable deleteBg = new GradientDrawable();
        deleteBg.setColor(0xffd00000);
        deleteBg.setCornerRadius(dp(6));
        deleteBg.setStroke(dp(1), 0xffff7777);
        deletePhotoButton.setBackground(deleteBg);
        deletePhotoButton.setPadding(dp(4), 0, dp(4), 0);
        deletePhotoButton.setOnClickListener(v -> confirmDeletePhoto());
        FrameLayout.LayoutParams deleteParams = new FrameLayout.LayoutParams(dp(68), dp(28));
        deleteParams.gravity = Gravity.TOP | Gravity.LEFT;
        deleteParams.setMargins(dp(6), dp(6), 0, 0);
        photoBox.addView(deletePhotoButton, deleteParams);

        topPane.addView(photoBox, new LinearLayout.LayoutParams(-1, 0, 1));

        descriptionEdit = new EditText(this);
        descriptionEdit.setHint("Напиши тут описание пресета");
        descriptionEdit.setMinLines(2);
        descriptionEdit.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                if (!loadingDescription && !rows.isEmpty()) rows.get(index).description = s.toString();
            }
            @Override public void afterTextChanged(Editable s) {}
        });
        topPane.addView(descriptionEdit, new LinearLayout.LayoutParams(-1, -2));

        LinearLayout bottomPane = new LinearLayout(this);
        bottomPane.setOrientation(LinearLayout.VERTICAL);

        LinearLayout cameraRow = buttonRow();
        TextView cameraLabel = new TextView(this);
        cameraLabel.setText("Камера");
        cameraLabel.setTextColor(BRAND_SILVER);
        cameraLabel.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        cameraLabel.setGravity(Gravity.CENTER_VERTICAL);
        cameraRow.addView(cameraLabel, new LinearLayout.LayoutParams(0, -2, 1));

        cameraSpinner = new Spinner(this);
        ArrayAdapter<String> cameraAdapter = new ArrayAdapter<>(this, android.R.layout.simple_spinner_item, new String[]{"Задняя камера", "Передняя камера"});
        cameraAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        cameraSpinner.setAdapter(cameraAdapter);
        cameraSpinner.setSelection(lensFacing == CameraSelector.LENS_FACING_FRONT ? 1 : 0);
        cameraSpinner.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                lensFacing = position == 1 ? CameraSelector.LENS_FACING_FRONT : CameraSelector.LENS_FACING_BACK;
            }
            @Override public void onNothingSelected(AdapterView<?> parent) {}
        });
        cameraRow.addView(cameraSpinner, new LinearLayout.LayoutParams(0, -2, 2));
        bottomPane.addView(cameraRow, new LinearLayout.LayoutParams(-1, -2));

        summaryText = new TextView(this);
        summaryText.setText(rows.isEmpty() ? "XML не загружен" : "Строк: " + rows.size());
        bottomPane.addView(summaryText);

        listView = new ListView(this);
        adapter = presetListAdapter();
        listView.setAdapter(adapter);
        listView.setOnItemClickListener((parent, view, position, id) -> {
            saveDescription();
            index = position;
            tempPhoto = null;
            tempPhotoIndex = -1;
            showCurrent();
        });
        listView.setOnItemLongClickListener((parent, view, position, id) -> {
            index = position;
            showCurrent();
            confirmDeleteRow(position);
            return true;
        });
        bottomPane.addView(listView, new LinearLayout.LayoutParams(-1, 0, 1));

        LinearLayout actionRow = buttonRow();
        photoButton = new Button(this);
        photoButton.setOnClickListener(v -> openCameraFromCurrent());
        actionRow.addView(photoButton, buttonParams());

        useButton = new Button(this);
        useButton.setText("Готово");
        useButton.setOnClickListener(v -> usePhoto());
        actionRow.addView(useButton, buttonParams());

        retakeButton = new Button(this);
        retakeButton.setText("Переснять");
        retakeButton.setOnClickListener(v -> openCameraFromCurrent());
        actionRow.addView(retakeButton, buttonParams());

        addButton = new Button(this);
        addButton.setText("Добавить");
        addButton.setOnClickListener(v -> addPhotoRowAfterCurrent());
        actionRow.addView(addButton, buttonParams());

        bottomPane.addView(actionRow, new LinearLayout.LayoutParams(-1, -2));

        if (landscape) {
            root.addView(topPane, new LinearLayout.LayoutParams(0, -1, 1));
            root.addView(bottomPane, new LinearLayout.LayoutParams(0, -1, 1));
        } else {
            root.addView(topPane, new LinearLayout.LayoutParams(-1, 0, 1));
            root.addView(bottomPane, new LinearLayout.LayoutParams(-1, 0, 1));
        }

        setContentView(root);
        refreshList();
        showCurrent();
    }

    private void openCameraFromCurrent() {
        if (rows.isEmpty()) return;
        saveDescription();
        showCameraScreen();
    }

    private void showCameraScreen() {
        currentScreen = "camera";
        cameraScreen = true;
        boolean landscape = getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE;
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(BRAND_BLACK);

        cameraPreview = new PreviewView(this);
        cameraPreview.setScaleType(PreviewView.ScaleType.FILL_CENTER);
        cameraPreview.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        root.addView(cameraPreview, new FrameLayout.LayoutParams(-1, -1));

        Button shutter = new Button(this);
        shutter.setText("");
        shutter.setContentDescription("Фото");
        GradientDrawable shutterBg = new GradientDrawable();
        shutterBg.setShape(GradientDrawable.OVAL);
        shutterBg.setColor(Color.WHITE);
        shutterBg.setStroke(dp(5), 0xffdddddd);
        shutter.setBackground(shutterBg);
        shutter.setOnClickListener(v -> capturePhoto());
        int size = dp(78);
        FrameLayout.LayoutParams shutterParams = new FrameLayout.LayoutParams(size, size);
        shutterParams.gravity = landscape ? (Gravity.RIGHT | Gravity.CENTER_VERTICAL) : (Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        shutterParams.setMargins(dp(20), dp(20), dp(20), dp(26));
        root.addView(shutter, shutterParams);

        SeekBar zoom = new SeekBar(this);
        zoom.setMax(100);
        zoom.setProgress(0);
        zoom.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                if (!fromUser || boundCamera == null) return;
                try {
                    Float min = boundCamera.getCameraInfo().getZoomState().getValue().getMinZoomRatio();
                    Float max = boundCamera.getCameraInfo().getZoomState().getValue().getMaxZoomRatio();
                    float ratio = min + (max - min) * (progress / 100f);
                    boundCamera.getCameraControl().setZoomRatio(ratio);
                } catch (Exception ignored) {
                }
            }
            @Override public void onStartTrackingTouch(SeekBar seekBar) {}
            @Override public void onStopTrackingTouch(SeekBar seekBar) {}
        });
        FrameLayout.LayoutParams zoomParams = new FrameLayout.LayoutParams(
                landscape ? dp(220) : -1,
                -2
        );
        zoomParams.gravity = landscape ? (Gravity.RIGHT | Gravity.BOTTOM) : (Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        zoomParams.setMargins(dp(24), dp(24), landscape ? dp(110) : dp(24), landscape ? dp(24) : dp(116));
        root.addView(zoom, zoomParams);

        setContentView(root);
        cameraPreview.post(this::ensureCamera);
    }

    private void moveSelection(int direction) {
        if (rows.isEmpty()) return;
        saveDescription();
        tempPhoto = null;
        tempPhotoIndex = -1;
        index = (index + direction + rows.size()) % rows.size();
        showCurrent();
    }

    private void refreshActionButtons() {
        if (rows.isEmpty() || photoButton == null) return;
        PassportRow row = rows.get(index);
        boolean hasPhoto = row.photoFile != null && row.photoFile.exists();
        boolean pending = tempPhoto != null && tempPhoto.exists() && tempPhotoIndex == index;

        if (prevButton != null) prevButton.setVisibility(pending ? View.GONE : View.VISIBLE);
        if (nextButton != null) nextButton.setVisibility(pending ? View.GONE : View.VISIBLE);
        photoButton.setVisibility(pending ? View.GONE : View.VISIBLE);
        useButton.setVisibility(pending ? View.VISIBLE : View.GONE);
        retakeButton.setVisibility(pending ? View.VISIBLE : View.GONE);
        photoButton.setText(hasPhoto ? "Переснять" : "Фото");
        if (addButton != null) addButton.setVisibility(!pending && hasPhoto ? View.VISIBLE : View.GONE);
    }

    private void openXml() {
        if (!ensureStorageAccess()) return;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        startActivityForResult(intent, REQ_XML);
    }

    private void openPartituraXml() {
        if (!ensureStorageAccess()) return;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        startActivityForResult(intent, REQ_PARTITURA_XML);
    }

    private void openProjectXml() {
        if (!ensureStorageAccess()) return;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        startActivityForResult(intent, REQ_PROJECT_XML);
    }

    private void showProjectListScreen() {
        showProjectListScreen("presets");
    }

    private void showProjectListScreen(String mode) {
        showProjectListScreen(mode, false);
    }

    private void showProjectListScreen(String mode, boolean remoteFresh) {
        if (projectBrowserCloud) remoteMode = true;
        if (!projectBrowserCloud) remoteMode = false;
        if (projectBrowserCloud && !remoteFresh) {
            showLoadingScreen("Обновляю проекты с сервера...");
            cameraExecutor.execute(() -> {
                boolean ok = refreshRemoteCache();
                runOnUiThread(() -> {
                    if (ok) {
                        showProjectListScreen(mode, true);
                    } else {
                        Toast.makeText(this, "Не удалось обновить облако", Toast.LENGTH_LONG).show();
                        showProjectSourceScreen();
                    }
                });
            });
            return;
        }
        if (!ensureStorageAccess()) return;
        currentScreen = "project_list";
        cameraScreen = false;
        filesScreenProjectDir = null;
        projectListMode = mode;
        stopCamera();

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 24);

        TextView title = new TextView(this);
        title.setText(projectBrowserCloud ? "Проекты: облако" : "Проекты: устройство");
        title.setTextSize(24);
        title.setGravity(Gravity.CENTER);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(title, new LinearLayout.LayoutParams(-1, -2));

        if (!projectBrowserCloud) {
            Button create = new Button(this);
            create.setText("Создать новый проект");
            create.setOnClickListener(v -> openXml());
            LinearLayout.LayoutParams createParams = new LinearLayout.LayoutParams(-1, -2);
            createParams.setMargins(0, dp(16), 0, dp(10));
            root.addView(create, createParams);
        }

        ScrollView scroll = new ScrollView(this);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(list, new ScrollView.LayoutParams(-1, -2));
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        try {
            File rootDir = projectBrowserCloud ? remoteCacheRootDir() : localPassportsRootDir();
            File[] dirs = rootDir.listFiles(file -> file.isDirectory() && (projectBrowserCloud || findProjectXml(file) != null));
            if (dirs == null || dirs.length == 0) {
                TextView empty = new TextView(this);
                empty.setText(projectBrowserCloud ? "В облаке пока нет проектов" : "Пока нет проектов");
                empty.setPadding(0, dp(24), 0, 0);
                empty.setTextColor(BRAND_MUTED);
                empty.setGravity(Gravity.CENTER);
                list.addView(empty, new LinearLayout.LayoutParams(-1, -2));
            } else {
                for (File dir : dirs) {
                    list.addView(projectRow(dir));
                }
            }
        } catch (Exception e) {
            Toast.makeText(this, "Проекты: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }

        Button backButton = new Button(this);
        backButton.setText("Назад");
        backButton.setOnClickListener(v -> showProjectSourceScreen());
        root.addView(backButton, new LinearLayout.LayoutParams(-1, -2));
        setContentView(root);
    }

    private View projectRow(File dir) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(16), dp(14), dp(16), dp(14));
        row.setBackground(rounded(BRAND_BLACK, BRAND_YELLOW, dp(2), dp(8)));
        row.setClickable(true);
        row.setFocusable(true);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(0, dp(6), 0, dp(6));
        row.setLayoutParams(params);

        TextView name = new TextView(this);
        name.setText(displayTitle(projectTitleFromDir(dir)));
        name.setTextColor(BRAND_YELLOW);
        name.setTextSize(18);
        name.setGravity(Gravity.CENTER);
        name.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        row.addView(name, new LinearLayout.LayoutParams(-1, -2));

        View.OnClickListener openProject = v -> showProjectModeScreen(dir, projectBrowserCloud);
        View.OnLongClickListener menu = v -> {
            showProjectMenu(dir);
            return true;
        };
        row.setOnClickListener(openProject);
        row.setOnLongClickListener(menu);
        name.setOnClickListener(openProject);
        name.setOnLongClickListener(menu);
        return row;
    }

    private void showProjectMenu(File dir) {
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        actions.setPadding(dp(18), dp(12), dp(18), dp(8));

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle(displayTitle(projectTitleFromDir(dir)))
                .setView(actions)
                .create();

        if (!projectBrowserCloud) {
            actions.addView(menuButton("Открыть", v -> {
                dialog.dismiss();
                showProjectModeScreen(dir, false);
            }));
            actions.addView(menuButton("Переименовать", v -> {
                dialog.dismiss();
                renameProject(dir);
            }));
            actions.addView(menuButton("Загрузить в облако", v -> {
                dialog.dismiss();
                saveProjectToRemoteWithConfirm(dir);
            }));
            actions.addView(menuButton("Удалить", v -> {
                dialog.dismiss();
                confirmDeleteProject(dir);
            }));
        } else {
            actions.addView(menuButton("Переименовать", v -> {
                dialog.dismiss();
                renameProject(dir);
            }));
            actions.addView(menuButton("Загрузить на устройство", v -> {
                dialog.dismiss();
                saveProjectToLocal(dir);
            }));
            actions.addView(menuButton("Удалить", v -> {
                dialog.dismiss();
                confirmDeleteProject(dir);
            }));
        }
        dialog.show();
    }

    private Button menuButton(String title, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(title);
        button.setTextSize(18);
        button.setOnClickListener(listener);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, dp(58));
        params.setMargins(0, dp(7), 0, dp(7));
        button.setLayoutParams(params);
        return button;
    }

    private void showProjectModeScreen(File dir, boolean cloudProject) {
        currentScreen = "project_mode";
        cameraScreen = false;
        filesScreenProjectDir = null;
        projectModeDir = dir;
        projectModeCloud = cloudProject;
        stopCamera();

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(24), dp(24), dp(24), dp(24));

        TextView title = new TextView(this);
        title.setText(displayTitle(projectTitleFromDir(dir)));
        title.setTextSize(24);
        title.setGravity(Gravity.CENTER);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(title, new LinearLayout.LayoutParams(-1, -2));

        addSpacer(root, 1);
        root.addView(projectKindButton(dir, cloudProject, "presets"));
        root.addView(projectKindButton(dir, cloudProject, "partitura"));
        addSpacer(root, 1);

        Button back = new Button(this);
        back.setText("Назад");
        back.setOnClickListener(v -> showProjectListScreen("projects", !projectBrowserCloud));
        root.addView(back, new LinearLayout.LayoutParams(-1, -2));

        setContentView(root);
    }

    private View projectKindButton(File dir, boolean cloudProject, String kind) {
        Button button = new Button(this);
        button.setText("presets".equals(kind) ? "Пресеты" : "Партитура");
        button.setTextSize(22);
        button.setMinHeight(dp(82));
        button.setOnClickListener(v -> {
            if (cloudProject) {
                showProjectFilesScreen(dir, kind);
            } else if ("presets".equals(kind)) {
                openExistingProjectDir(dir);
            } else {
                selectedPartituraProjectDir = dir;
                showPartituraSetupScreen();
            }
        });
        button.setOnLongClickListener(v -> {
            showProjectKindMenu(dir, cloudProject, kind);
            return true;
        });
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, dp(88));
        params.setMargins(0, dp(10), 0, dp(10));
        button.setLayoutParams(params);
        return button;
    }

    private void showProjectKindMenu(File dir, boolean cloudProject, String kind) {
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.VERTICAL);
        actions.setPadding(dp(18), dp(12), dp(18), dp(8));
        String title = ("presets".equals(kind) ? "Пресеты" : "Партитура") + ": " + displayTitle(projectTitleFromDir(dir));
        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle(title)
                .setView(actions)
                .create();
        if (!cloudProject) {
            actions.addView(menuButton("Открыть", v -> {
                dialog.dismiss();
                if ("presets".equals(kind)) openExistingProjectDir(dir);
                else {
                    selectedPartituraProjectDir = dir;
                    showPartituraSetupScreen();
                }
            }));
        }
        if (!cloudProject) {
            actions.addView(menuButton("Файлы", v -> {
                dialog.dismiss();
                showProjectFilesScreen(dir, kind);
            }));
        }
        if (cloudProject) {
            actions.addView(menuButton("Загрузить на устройство", v -> {
                dialog.dismiss();
                saveProjectToLocal(dir);
            }));
        } else {
            actions.addView(menuButton("Загрузить в облако", v -> {
                dialog.dismiss();
                saveProjectToRemoteWithConfirm(dir);
            }));
        }
        dialog.show();
    }

    private void openProjectFiles(File dir) {
        try {
            String rel = "primary:Documents/MA2_passports/" + dir.getName();
            Uri documentUri = DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", rel);
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(documentUri, DocumentsContract.Document.MIME_TYPE_DIR);
            intent.setClassName("com.google.android.documentsui", "com.android.documentsui.files.FilesActivity");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            startActivity(intent);
        } catch (Exception e) {
            try {
                String rel = "primary:Documents/MA2_passports/" + dir.getName();
                Uri documentUri = DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", rel);
                Intent files = new Intent(Intent.ACTION_VIEW);
                files.setDataAndType(documentUri, DocumentsContract.Document.MIME_TYPE_DIR);
                files.setClassName("com.google.android.apps.nbu.files", "com.google.android.apps.nbu.files.gateway.browse.BrowseGatewayHandler");
                files.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
                startActivity(files);
            } catch (Exception ignored) {
                Toast.makeText(this, dir.getAbsolutePath(), Toast.LENGTH_LONG).show();
            }
        }
    }

    private void showProjectFilesScreen(File dir) {
        showProjectFilesScreen(dir, "presets");
    }

    private void showProjectFilesScreen(File dir, String kind) {
        if (projectModeCloud) remoteMode = true;
        if (projectModeCloud) {
            showLoadingScreen("Обновляю файлы проекта...");
            cameraExecutor.execute(() -> {
                try {
                    File fresh = refreshRemoteProjectFiles(dir.getName(), kind);
                    runOnUiThread(() -> showProjectFilesScreenReady(fresh, kind));
                } catch (Exception e) {
                    runOnUiThread(() -> {
                        Toast.makeText(this, "Сервер: " + e.getMessage(), Toast.LENGTH_LONG).show();
                        showProjectModeScreen(dir, true);
                    });
                }
            });
            return;
        }
        showProjectFilesScreenReady(dir, kind);
    }

    private void showProjectFilesScreenReady(File dir, String kind) {
        currentScreen = "project_files";
        cameraScreen = false;
        filesScreenProjectDir = dir;
        filesScreenKind = kind;
        stopCamera();

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 24);

        TextView title = new TextView(this);
        title.setText("Файлы: " + displayTitle(projectTitleFromDir(dir)));
        title.setTextSize(20);
        title.setTextColor(BRAND_TEXT);
        root.addView(title, new LinearLayout.LayoutParams(-1, -2));

        ScrollView scroll = new ScrollView(this);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(list, new ScrollView.LayoutParams(-1, -2));
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        ArrayList<File> files = projectFiles(dir, filesScreenKind);
        if (files.isEmpty()) {
            TextView empty = new TextView(this);
            empty.setText("presets".equals(filesScreenKind) ? "Паспорт пока не создан" : "Партитура пока не создана");
            empty.setPadding(0, dp(24), 0, 0);
            empty.setTextColor(BRAND_MUTED);
            list.addView(empty, new LinearLayout.LayoutParams(-1, -2));
        } else {
            for (File file : files) {
                list.addView(fileRow(dir, file));
            }
        }

        Button back = new Button(this);
        back.setText("Назад");
        back.setOnClickListener(v -> {
            if (projectModeDir != null) showProjectModeScreen(projectModeDir, projectModeCloud);
            else showProjectListScreen(filesScreenKind);
        });
        root.addView(back, new LinearLayout.LayoutParams(-1, -2));

        setContentView(root);
    }

    private View fileRow(File project, File file) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(dp(16), dp(14), dp(16), dp(14));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(BRAND_BLACK);
        bg.setCornerRadius(dp(8));
        bg.setStroke(dp(2), BRAND_YELLOW);
        row.setBackground(bg);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(0, dp(8), 0, dp(8));
        row.setLayoutParams(params);
        row.setClickable(true);
        row.setFocusable(true);

        TextView name = new TextView(this);
        name.setText(fileLabel(project, file));
        name.setTextSize(16);
        name.setTextColor(BRAND_YELLOW);
        name.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        row.addView(name, new LinearLayout.LayoutParams(-1, -2));

        TextView meta = new TextView(this);
        meta.setText(readableSize(file.length()));
        meta.setTextColor(BRAND_TEXT);
        meta.setPadding(0, dp(4), 0, 0);
        row.addView(meta, new LinearLayout.LayoutParams(-1, -2));

        row.setOnClickListener(v -> openFile(file));
        row.setOnLongClickListener(v -> {
            showFileMenu(project, file);
            return true;
        });
        return row;
    }

    private void showFileMenu(File project, File file) {
        String[] actions = {"Отправить", "Удалить"};
        new AlertDialog.Builder(this)
                .setTitle(fileLabel(project, file))
                .setItems(actions, (dialog, which) -> {
                    if (which == 0) shareFile(file);
                    else if (which == 1) confirmDeleteFile(project, file);
                })
                .show();
    }

    private ArrayList<File> projectFiles(File dir) {
        return projectFiles(dir, "presets");
    }

    private ArrayList<File> projectFiles(File dir, String kind) {
        ArrayList<File> result = new ArrayList<>();
        File[] top = dir.listFiles(file -> {
            if (!file.isFile()) return false;
            String name = file.getName().toLowerCase(Locale.ROOT);
            if ("partitura".equals(kind)) {
                return name.endsWith("_партитура.xlsx")
                        || name.endsWith("_партитура.pdf")
                        || name.endsWith("_new.xml");
            }
            return name.endsWith("_пресеты.xlsx") || name.endsWith("_пресеты.pdf");
        });
        if (top != null) {
            for (File file : top) result.add(file);
        }
        return result;
    }

    private String fileLabel(File project, File file) {
        File parent = file.getParentFile();
        if (parent != null && "photos".equals(parent.getName())) return "photos/" + file.getName();
        return file.getName();
    }

    private void openFile(File file) {
        try {
            Uri uri = uriForFile(file);
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, mimeFor(file));
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivity(Intent.createChooser(intent, "Открыть файл"));
        } catch (Exception e) {
            Toast.makeText(this, "Открыть: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void shareFile(File file) {
        try {
            Uri uri = uriForFile(file);
            Intent intent = new Intent(Intent.ACTION_SEND);
            intent.setType(mimeFor(file));
            intent.putExtra(Intent.EXTRA_STREAM, uri);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivity(Intent.createChooser(intent, "Отправить файл"));
        } catch (Exception e) {
            Toast.makeText(this, "Отправить: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private Uri uriForFile(File file) {
        return FileProvider.getUriForFile(this, getPackageName() + ".fileprovider", file);
    }

    private String mimeFor(File file) {
        String name = file.getName().toLowerCase(Locale.ROOT);
        if (name.endsWith(".xlsx")) return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
        if (name.endsWith(".xml")) return "text/xml";
        if (name.endsWith(".pdf")) return "application/pdf";
        if (name.endsWith(".jpg") || name.endsWith(".jpeg")) return "image/jpeg";
        if (name.endsWith(".png")) return "image/png";
        String ext = "";
        int dot = name.lastIndexOf('.');
        if (dot >= 0 && dot + 1 < name.length()) ext = name.substring(dot + 1);
        String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
        return mime == null ? "*/*" : mime;
    }

    private String readableSize(long bytes) {
        if (bytes < 1024) return bytes + " B";
        double kb = bytes / 1024.0;
        if (kb < 1024) return String.format(Locale.ROOT, "%.1f KB", kb);
        return String.format(Locale.ROOT, "%.1f MB", kb / 1024.0);
    }

    private void confirmDeleteFile(File project, File file) {
        new AlertDialog.Builder(this)
                .setTitle("Удалить файл?")
                .setMessage(file.getName())
                .setPositiveButton("Удалить", (dialog, which) -> {
                    if (file.delete()) {
                        Toast.makeText(this, "Удалено", Toast.LENGTH_SHORT).show();
                    } else {
                        Toast.makeText(this, "Не удалось удалить", Toast.LENGTH_LONG).show();
                    }
                    showProjectFilesScreen(project, filesScreenKind);
                })
                .setNegativeButton("Отмена", null)
                .show();
    }

    private void renameProject(File dir) {
        EditText input = new EditText(this);
        input.setText(displayTitle(projectTitleFromDir(dir)));
        input.setSelectAllOnFocus(true);
        new AlertDialog.Builder(this)
                .setTitle("Переименовать проект")
                .setView(input)
                .setPositiveButton("Переименовать", (dialog, which) -> {
                    try {
                        String title = input.getText().toString().trim();
                        if (title.isEmpty()) return;
                        File newDir = new File(dir.getParentFile(), safe(title) + "_passport");
                        if (newDir.exists()) throw new Exception("Такой проект уже есть");
                        if (!dir.renameTo(newDir)) throw new Exception("Не удалось переименовать папку");
                        File xml = findProjectXml(newDir);
                        if (xml != null) {
                            File renamedXml = new File(newDir, safe(title) + ".xml");
                            if (!xml.getName().equals(renamedXml.getName())) xml.renameTo(renamedXml);
                        }
                        if (remoteMode) {
                            deleteRemoteProject(dir.getName());
                            syncProjectToRemote(newDir);
                        }
                        showProjectListScreen();
                    } catch (Exception e) {
                        Toast.makeText(this, "Переименование: " + e.getMessage(), Toast.LENGTH_LONG).show();
                    }
                })
                .setNegativeButton("Отмена", null)
                .show();
    }

    private void confirmDeleteProject(File dir) {
        new AlertDialog.Builder(this)
                .setTitle("Удалить проект?")
                .setMessage(displayTitle(projectTitleFromDir(dir)))
                .setPositiveButton("Удалить", (dialog, which) -> {
                    deleteRecursive(dir);
                    if (remoteMode) deleteRemoteProject(dir.getName());
                    showProjectListScreen();
                })
                .setNegativeButton("Отмена", null)
                .show();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQ_XML && resultCode == RESULT_OK && data != null) {
            loadXml(data.getData());
        } else if (requestCode == REQ_PARTITURA_XML && resultCode == RESULT_OK && data != null) {
            loadPartituraXml(data.getData());
        } else if (requestCode == REQ_PROJECT_XML && resultCode == RESULT_OK && data != null) {
            openExistingProjectXml(data.getData());
        } else if (requestCode == REQ_IMPORT_PHOTO && resultCode == RESULT_OK && data != null) {
            importPhotoFromUri(data.getData());
        }
    }

    @Override
    public void onConfigurationChanged(@NonNull Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        saveDescription();
        if (cameraScreen) {
            showCameraScreen();
        } else if ("project_files".equals(currentScreen) && filesScreenProjectDir != null) {
            showProjectFilesScreenReady(filesScreenProjectDir, filesScreenKind);
        } else if ("project_mode".equals(currentScreen) && projectModeDir != null) {
            showProjectModeScreen(projectModeDir, projectModeCloud);
        } else if ("project_list".equals(currentScreen)) {
            showProjectListScreen(projectListMode, true);
        } else if ("project_source".equals(currentScreen)) {
            showProjectSourceScreen();
        } else if ("partitura_setup".equals(currentScreen)) {
            showPartituraSetupScreen();
        } else if (projectDir != null && !rows.isEmpty()) {
            showPresetWorkspace();
        } else {
            showStartScreen();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        saveDescription();
        try {
            writePassportNow();
        } catch (Exception ignored) {
        }
        if (cameraExecutor != null) cameraExecutor.shutdown();
    }

    @Override
    protected void onPause() {
        super.onPause();
        saveDescription();
        savePassportQuietly();
    }

    @Override
    public void onBackPressed() {
        if (cameraScreen) {
            showPresetWorkspace();
            return;
        }
        if ("project_files".equals(currentScreen) || filesScreenProjectDir != null) {
            filesScreenProjectDir = null;
            if (projectModeDir != null) showProjectModeScreen(projectModeDir, projectModeCloud);
            else showProjectListScreen(filesScreenKind);
            return;
        }
        if ("project_mode".equals(currentScreen)) {
            showProjectListScreen("projects", !projectBrowserCloud);
            return;
        }
        if ("project_list".equals(currentScreen)) {
            showProjectSourceScreen();
            return;
        }
        if ("project_source".equals(currentScreen)) {
            showStartScreen();
            return;
        }
        if ("preset_setup".equals(currentScreen) || "partitura_setup".equals(currentScreen)) {
            if (projectModeDir != null) showProjectModeScreen(projectModeDir, projectModeCloud);
            else showStartScreen();
            return;
        }
        if ("loading".equals(currentScreen)) {
            return;
        }
        if (projectDir != null && !rows.isEmpty()) {
            new AlertDialog.Builder(this)
                    .setTitle("Сохранить таблицу?")
                    .setMessage("Собрать паспорт с текущими фото и вернуться на главный экран?")
                    .setPositiveButton("Сохранить", (dialog, which) -> saveProjectAndReturnToStart())
                    .setNegativeButton("Не сохранять", (dialog, which) -> {
                        tempPhoto = null;
                        tempPhotoIndex = -1;
                        projectDir = null;
                        photosDir = null;
                        items.clear();
                        rows.clear();
                        listLabels.clear();
                        showStartScreen();
                    })
                    .setNeutralButton("Отмена", null)
                    .show();
            return;
        }
        super.onBackPressed();
    }

    private void saveProjectAndReturnToStart() {
        saveDescription();
        Toast.makeText(this, "Собираю таблицу...", Toast.LENGTH_SHORT).show();
        cameraExecutor.execute(() -> {
            try {
                writePassportNow();
                runOnUiThread(() -> {
                    Toast.makeText(this, "Таблица сохранена", Toast.LENGTH_SHORT).show();
                    File savedProjectDir = projectDir;
                    tempPhoto = null;
                    tempPhotoIndex = -1;
                    projectDir = null;
                    photosDir = null;
                    items.clear();
                    rows.clear();
                    listLabels.clear();
                    if (savedProjectDir != null) showProjectFilesScreen(savedProjectDir);
                    else showStartScreen();
                });
            } catch (Exception e) {
                runOnUiThread(() -> Toast.makeText(this, "Сохранение: " + e.getMessage(), Toast.LENGTH_LONG).show());
            }
        });
    }

    private void loadXml(Uri uri) {
        String defaultName = stripExtension(getFileName(uri));
        EditText input = new EditText(this);
        input.setText(defaultName);
        input.setSelectAllOnFocus(true);
        new AlertDialog.Builder(this)
                .setTitle("Название спектакля")
                .setView(input)
                .setPositiveButton("Открыть", (dialog, which) -> {
                    String title = input.getText().toString().trim();
                    loadXmlWithTitle(uri, title.isEmpty() ? defaultName : title);
                })
                .setNegativeButton("Отмена", null)
                .show();
    }

    private void loadPartituraXml(Uri uri) {
        String defaultName = stripExtension(getFileName(uri));
        EditText input = new EditText(this);
        input.setText(defaultName);
        input.setSelectAllOnFocus(true);
        new AlertDialog.Builder(this)
                .setTitle("Название спектакля")
                .setView(input)
                .setPositiveButton("Открыть", (dialog, which) -> {
                    String title = input.getText().toString().trim();
                    createPartituraProjectFromXml(uri, title.isEmpty() ? defaultName : title);
                })
                .setNegativeButton("Отмена", null)
                .show();
    }

    private void createPartituraProjectFromXml(Uri uri, String title) {
        try {
            String safeTitle = safe(title);
            File projects = passportsRootDir();
            File dir = new File(projects, safeTitle + "_passport");
            File photos = new File(dir, "photos");
            if (!photos.exists() && !photos.mkdirs()) {
                throw new Exception("Не могу создать папку " + photos.getAbsolutePath());
            }
            File xmlCopy = new File(dir, safeTitle + ".xml");
            copy(getContentResolver().openInputStream(uri), xmlCopy);
            selectedPartituraProjectDir = dir;
            Toast.makeText(this, "Проект выбран: " + displayTitle(projectTitleFromDir(dir)), Toast.LENGTH_LONG).show();
            showPartituraSetupScreen();
        } catch (Exception e) {
            Toast.makeText(this, "XML: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void loadXmlWithTitle(Uri uri, String title) {
        showLoadingScreen("Загружаю XML...");
        cameraExecutor.execute(() -> {
            try {
                showTitle = title;
                File projects = passportsRootDir();
                projectDir = new File(projects, safe(showTitle) + "_passport");
                boolean existingProject = projectDir.exists();
                photosDir = new File(projectDir, "photos");
                if (!photosDir.exists() && !photosDir.mkdirs()) {
                    throw new Exception("Не могу создать папку " + photosDir.getAbsolutePath());
                }

                File xmlCopy = new File(projectDir, safe(showTitle) + ".xml");
                InputStream input = getContentResolver().openInputStream(uri);
                if (input == null) throw new Exception("Android не отдал XML файл");
                copy(input, xmlCopy);
                loadProjectData(xmlCopy, !existingProject);

                index = 0;
                running = false;
                tempPhoto = null;
                tempPhotoIndex = -1;
                writePassportNow();
                int count = items.size();
                runOnUiThread(() -> {
                    showPresetWorkspace();
                    Toast.makeText(this, "XML загружен: " + count + " строк", Toast.LENGTH_LONG).show();
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    Toast.makeText(this, "Ошибка XML: " + e.getMessage(), Toast.LENGTH_LONG).show();
                    showPresetSetupScreen();
                });
            }
        });
    }

    private void openExistingProjectDir(File dir) {
        remoteMode = false;
        showLoadingScreen("Открываю проект...");
        cameraExecutor.execute(() -> {
            try {
                File freshDir = dir;
                File xmlCopy = findProjectXml(freshDir);
                if (xmlCopy == null || !xmlCopy.exists()) {
                    throw new Exception("В папке нет XML");
                }
                projectDir = freshDir;
                photosDir = new File(projectDir, "photos");
                if (!photosDir.exists() && !photosDir.mkdirs()) {
                    throw new Exception("Не могу открыть photos");
                }
                showTitle = projectTitleFromDir(projectDir);
                loadProjectData(xmlCopy, false);
                index = 0;
                tempPhoto = null;
                tempPhotoIndex = -1;
                runOnUiThread(() -> {
                    showPresetWorkspace();
                    Toast.makeText(this, "Проект открыт: " + showTitle, Toast.LENGTH_LONG).show();
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    Toast.makeText(this, "Проект: " + e.getMessage(), Toast.LENGTH_LONG).show();
                    if (projectModeDir != null) showProjectModeScreen(projectModeDir, projectModeCloud);
                    else showProjectListScreen();
                });
            }
        });
    }

    private void openExistingProjectXml(Uri uri) {
        String defaultName = "show";
        try {
            File xmlCopy = resolveExistingProjectFile(uri);
            if (xmlCopy == null || !xmlCopy.exists()) {
                throw new Exception("Выбери show.xml внутри папки проекта");
            }
            projectDir = xmlCopy.getParentFile();
            photosDir = new File(projectDir, "photos");
            if (!photosDir.exists() && !photosDir.mkdirs()) {
                throw new Exception("Не могу открыть photos");
            }
            showTitle = projectTitleFromDir(projectDir);
            loadProjectData(xmlCopy, false);
            index = 0;
            tempPhoto = null;
            tempPhotoIndex = -1;
            showPresetWorkspace();
            Toast.makeText(this, "Проект открыт: " + showTitle, Toast.LENGTH_LONG).show();
        } catch (Exception e) {
            Toast.makeText(this, "Проект: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private File resolveExistingProjectFile(Uri uri) throws Exception {
        File root = passportsRootDir();
        if (DocumentsContract.isDocumentUri(this, uri)) {
            String docId = DocumentsContract.getDocumentId(uri);
            int marker = docId.indexOf("Documents/MA2_passports/");
            if (marker >= 0) {
                String rel = docId.substring(marker + "Documents/MA2_passports/".length());
                File candidate = new File(root, rel);
                if (candidate.exists()) return candidate;
            }
            marker = docId.indexOf("Documents/MA2_pasports/");
            if (marker >= 0) {
                String rel = docId.substring(marker + "Documents/MA2_pasports/".length());
                File candidate = new File(root, rel);
                if (candidate.exists()) return candidate;
            }
        }
        String path = uri.getPath();
        if (path != null) {
            int marker = path.indexOf("MA2_passports/");
            if (marker >= 0) {
                String rel = path.substring(marker + "MA2_passports/".length());
                int colon = rel.indexOf(':');
                if (colon >= 0) rel = rel.substring(colon + 1);
                File candidate = new File(root, rel);
                if (candidate.exists()) return candidate;
            }
            marker = path.indexOf("MA2_pasports/");
            if (marker >= 0) {
                String rel = path.substring(marker + "MA2_pasports/".length());
                int colon = rel.indexOf(':');
                if (colon >= 0) rel = rel.substring(colon + 1);
                File candidate = new File(root, rel);
                if (candidate.exists()) return candidate;
            }
        }
        String selectedName = getFileName(uri);
        if (!selectedName.toLowerCase(Locale.ROOT).endsWith(".xml")) return null;
        throw new Exception("Android не отдал путь к файлу. Открой проект из списка или выбери XML через файловый менеджер Документы");
    }

    private boolean ensureStorageAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !Environment.isExternalStorageManager()) {
            Toast.makeText(this, "Разреши доступ к файлам, чтобы сохранять в Документы/MA2_passports", Toast.LENGTH_LONG).show();
            Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
            intent.setData(Uri.parse("package:" + getPackageName()));
            startActivity(intent);
            return false;
        }
        return true;
    }

    private File passportsRootDir() throws Exception {
        if (remoteMode) {
            if (!ensureRemoteReady()) throw new Exception("Нет подключения к удаленному серверу");
            File root = remoteCacheRootDir();
            if (!root.exists() && !root.mkdirs()) {
                throw new Exception("Не могу создать кэш " + root.getAbsolutePath());
            }
            return root;
        }
        File documents = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS);
        File root = new File(documents, "MA2_passports");
        File oldRoot = new File(documents, "MA2_pasports");
        if (!root.exists() && oldRoot.exists()) {
            oldRoot.renameTo(root);
        } else if (root.exists() && oldRoot.exists()) {
            File[] oldProjects = oldRoot.listFiles();
            if (oldProjects != null) {
                for (File oldProject : oldProjects) {
                    File target = new File(root, oldProject.getName());
                    if (!target.exists()) oldProject.renameTo(target);
                }
            }
            File[] leftovers = oldRoot.listFiles();
            if (leftovers == null || leftovers.length == 0) oldRoot.delete();
        }
        if (!root.exists() && !root.mkdirs()) {
            throw new Exception("Не могу создать папку " + root.getAbsolutePath());
        }
        return root;
    }

    private File localPassportsRootDir() throws Exception {
        File documents = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS);
        File root = new File(documents, "MA2_passports");
        if (!root.exists() && !root.mkdirs()) {
            throw new Exception("Не могу создать папку " + root.getAbsolutePath());
        }
        return root;
    }

    private File remoteCacheRootDir() {
        return new File(getFilesDir(), "remote_cache/MA2_passports");
    }

    private void loadServerSettings() {
        SharedPreferences prefs = getSharedPreferences("cloud", MODE_PRIVATE);
        remoteMode = prefs.getBoolean("remoteMode", false);
        cloudProvider = prefs.getString("provider", "sftp");
        cloudUrl = prefs.getString("url", prefs.getString("host", ""));
        cloudPort = prefs.getInt("port", 22);
        cloudUser = prefs.getString("user", "");
        cloudPassword = prefs.getString("password", "");
        yandexAccessToken = prefs.getString("yandexAccessToken", "");
        yandexRefreshToken = prefs.getString("yandexRefreshToken", "");
        remoteBasePath = prefs.getString("remoteDir", REMOTE_ROOT_NAME);
    }

    private void saveServerSettings() {
        getSharedPreferences("cloud", MODE_PRIVATE).edit()
                .putBoolean("remoteMode", remoteMode)
                .putString("provider", cloudProvider)
                .putString("url", cloudUrl)
                .putInt("port", cloudPort)
                .putString("user", cloudUser)
                .putString("password", cloudPassword)
                .putString("yandexAccessToken", yandexAccessToken)
                .putString("yandexRefreshToken", yandexRefreshToken)
                .putString("remoteDir", remoteBasePath == null || remoteBasePath.isEmpty() ? REMOTE_ROOT_NAME : remoteBasePath)
                .apply();
    }

    private void tryConnectRemoteOnStart() {
        if ("yandex_disk".equals(cloudProvider)) {
            if (yandexAccessToken == null || yandexAccessToken.trim().isEmpty()) {
                remoteConnected = false;
                return;
            }
        } else if (cloudUrl == null || cloudUrl.trim().isEmpty() || cloudUser == null || cloudUser.trim().isEmpty()) {
            remoteConnected = false;
            return;
        }
        Executors.newSingleThreadExecutor().execute(() -> {
            boolean ok = ensureRemoteReady();
            runOnUiThread(() -> {
                remoteConnected = ok;
                if ("start".equals(currentScreen)) showStartScreen();
            });
        });
    }

    private void showSftpSettingsDialog() {
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(18), dp(10), dp(18), 0);
        Button yandexButton = new Button(this);
        yandexButton.setText("Подключить Яндекс.Диск");
        Button sftpLabel = new Button(this);
        sftpLabel.setText("SFTP");
        EditText host = dialogInput("SFTP сервер", cloudUrl);
        EditText port = dialogInput("Порт", String.valueOf(cloudPort));
        EditText user = dialogInput("Пользователь", cloudUser);
        EditText password = dialogInput("Пароль", cloudPassword);
        EditText remoteDir = dialogInput("Папка", remoteBasePath == null || remoteBasePath.isEmpty() ? REMOTE_ROOT_NAME : remoteBasePath);
        password.setInputType(0x00000081);
        form.addView(yandexButton);
        form.addView(sftpLabel);
        form.addView(host);
        form.addView(port);
        form.addView(user);
        form.addView(password);
        form.addView(remoteDir);
        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("Настройка облака")
                .setView(form)
                .setNegativeButton("Назад", null)
                .setPositiveButton("Подключить и сохранить", null)
                .create();
        yandexButton.setOnClickListener(v -> connectYandexDialog(dialog));
        dialog.setOnShowListener(d -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            cloudProvider = "sftp";
            cloudUrl = host.getText().toString().trim();
            try {
                cloudPort = Integer.parseInt(port.getText().toString().trim());
            } catch (Exception e) {
                Toast.makeText(this, "Порт должен быть числом", Toast.LENGTH_LONG).show();
                return;
            }
            cloudUser = user.getText().toString().trim();
            cloudPassword = password.getText().toString();
            remoteBasePath = remoteDir.getText().toString().trim().isEmpty() ? REMOTE_ROOT_NAME : remoteDir.getText().toString().trim();
            remoteMode = true;
            saveServerSettings();
            Toast.makeText(this, "Подключаюсь...", Toast.LENGTH_SHORT).show();
            Executors.newSingleThreadExecutor().execute(() -> {
                boolean ok = ensureRemoteReady();
                runOnUiThread(() -> {
                    if (ok) {
                        dialog.dismiss();
                        showStartScreen();
                    } else {
                        Toast.makeText(this, "Не удалось подключиться", Toast.LENGTH_LONG).show();
                    }
                });
            });
        }));
        dialog.show();
    }

    private void connectYandexDialog(AlertDialog parentDialog) {
        if (BuildConfig.YANDEX_CLIENT_ID == null || BuildConfig.YANDEX_CLIENT_ID.isEmpty()
                || BuildConfig.YANDEX_CLIENT_SECRET == null || BuildConfig.YANDEX_CLIENT_SECRET.isEmpty()) {
            Toast.makeText(this, "В сборке нет YANDEX_CLIENT_ID/YANDEX_CLIENT_SECRET", Toast.LENGTH_LONG).show();
            return;
        }
        try {
            String authUrl = "https://oauth.yandex.ru/authorize?"
                    + "response_type=code"
                    + "&client_id=" + URLEncoder.encode(BuildConfig.YANDEX_CLIENT_ID, "UTF-8")
                    + "&redirect_uri=" + URLEncoder.encode("https://oauth.yandex.ru/verification_code", "UTF-8")
                    + "&scope=" + URLEncoder.encode("cloud_api:disk.app_folder", "UTF-8")
                    + "&force_confirm=yes";
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(authUrl)));
        } catch (Exception e) {
            Toast.makeText(this, "Yandex: " + e.getMessage(), Toast.LENGTH_LONG).show();
            return;
        }
        EditText codeInput = dialogInput("Код подтверждения", "");
        new AlertDialog.Builder(this)
                .setTitle("Яндекс.Диск")
                .setMessage("Скопируй код из браузера и вставь сюда.")
                .setView(codeInput)
                .setNegativeButton("Отмена", null)
                .setPositiveButton("Подключить", (d, w) -> {
                    String code = codeInput.getText().toString().trim();
                    if (code.isEmpty()) return;
                    showLoadingScreen("Подключаю Яндекс.Диск...");
                    Executors.newSingleThreadExecutor().execute(() -> {
                        try {
                            JSONObject token = yandexExchangeCode(code);
                            yandexAccessToken = token.optString("access_token", "");
                            yandexRefreshToken = token.optString("refresh_token", "");
                            if (yandexAccessToken.isEmpty()) throw new Exception("Yandex не вернул access_token");
                            cloudProvider = "yandex_disk";
                            remoteMode = true;
                            saveServerSettings();
                            yandexEnsureDir("app:/" + REMOTE_ROOT_NAME);
                            refreshRemoteCache();
                            runOnUiThread(() -> {
                                if (parentDialog != null) parentDialog.dismiss();
                                remoteConnected = true;
                                showStartScreen();
                                Toast.makeText(this, "Яндекс.Диск подключен", Toast.LENGTH_LONG).show();
                            });
                        } catch (Exception e) {
                            runOnUiThread(() -> {
                                remoteConnected = false;
                                showStartScreen();
                                Toast.makeText(this, "Яндекс.Диск: " + e.getMessage(), Toast.LENGTH_LONG).show();
                            });
                        }
                    });
                })
                .show();
    }

    private JSONObject yandexExchangeCode(String code) throws Exception {
        String body = "grant_type=authorization_code"
                + "&code=" + URLEncoder.encode(code, "UTF-8")
                + "&client_id=" + URLEncoder.encode(BuildConfig.YANDEX_CLIENT_ID, "UTF-8")
                + "&client_secret=" + URLEncoder.encode(BuildConfig.YANDEX_CLIENT_SECRET, "UTF-8");
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        HttpURLConnection conn = (HttpURLConnection) new URL("https://oauth.yandex.ru/token").openConnection();
        conn.setRequestMethod("POST");
        conn.setDoOutput(true);
        conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded");
        conn.getOutputStream().write(bytes);
        int codeStatus = conn.getResponseCode();
        String response = readHttp(conn);
        if (codeStatus < 200 || codeStatus >= 300) throw new Exception("OAuth HTTP " + codeStatus + ": " + response);
        return new JSONObject(response);
    }

    private EditText dialogInput(String hint, String value) {
        EditText edit = new EditText(this);
        edit.setHint(hint);
        edit.setText(value);
        edit.setSingleLine(true);
        edit.setTextColor(BRAND_TEXT);
        edit.setHintTextColor(BRAND_MUTED);
        return edit;
    }

    private boolean ensureRemoteReady() {
        if (!remoteMode) return true;
        if ("yandex_disk".equals(cloudProvider)) {
            if (remoteConnected && yandexAccessToken != null && !yandexAccessToken.isEmpty()) return true;
            if (yandexAccessToken == null || yandexAccessToken.isEmpty()) return false;
            try {
                yandexEnsureDir("app:/" + REMOTE_ROOT_NAME);
                remoteConnected = true;
                return true;
            } catch (Exception e) {
                remoteConnected = false;
                return false;
            }
        }
        if (remoteConnected) return true;
        if (cloudUrl.isEmpty() || cloudUser.isEmpty()) return false;
        try {
            SftpHandle handle = openCloud();
            handle.close();
            remoteConnected = true;
            return true;
        } catch (Exception e) {
            remoteConnected = false;
            return false;
        }
    }

    private boolean refreshRemoteCache() {
        if (!remoteMode) return true;
        if ("yandex_disk".equals(cloudProvider)) {
            if (yandexAccessToken == null || yandexAccessToken.isEmpty()) return false;
            try {
                deleteRecursive(remoteCacheRootDir());
                yandexDownloadProjectIndex(remoteCacheRootDir());
                remoteConnected = true;
                return true;
            } catch (Exception e) {
                remoteConnected = false;
                return false;
            }
        }
        if (cloudUrl.isEmpty() || cloudUser.isEmpty()) return false;
        try {
            SftpHandle handle = openCloud();
            deleteRecursive(remoteCacheRootDir());
            downloadRemoteProjectIndex(handle.sftp, remoteBasePath, remoteCacheRootDir());
            handle.close();
            remoteConnected = true;
            return true;
        } catch (Exception e) {
            remoteConnected = false;
            return false;
        }
    }

    private File refreshRemoteProjectDir(String projectName) throws Exception {
        if (!remoteMode) return new File(remoteCacheRootDir(), projectName);
        if ("yandex_disk".equals(cloudProvider)) {
            File target = new File(remoteCacheRootDir(), projectName);
            yandexDownloadProject(projectName, target, null);
            remoteConnected = true;
            return target;
        }
        SftpHandle handle = openCloud();
        File target = new File(remoteCacheRootDir(), projectName);
        deleteRecursive(target);
        downloadRemoteDir(handle.sftp, sftpPath(remoteBasePath, projectName), target, null);
        handle.close();
        remoteConnected = true;
        return target;
    }

    private File refreshRemoteProjectFiles(String projectName, String kind) throws Exception {
        File target = new File(remoteCacheRootDir(), projectName);
        deleteRecursive(target);
        if (!target.mkdirs()) throw new Exception("Не могу создать кэш проекта");
        if ("yandex_disk".equals(cloudProvider)) {
            JSONArray entries = yandexList(yandexProjectPath(projectName));
            for (int i = 0; i < entries.length(); i++) {
                JSONObject item = entries.optJSONObject(i);
                if (item == null || !"file".equals(item.optString("type"))) continue;
                String name = item.optString("name", "");
                if (!isProjectOutputFile(name, kind)) continue;
                yandexGetFile(yandexHref("resources/download", item.optString("path"), false), new File(target, name));
            }
            remoteConnected = true;
            return target;
        }
        SftpHandle handle = openCloud();
        try {
            String remoteProject = sftpPath(remoteBasePath, projectName);
            for (CloudEntry entry : listRemoteDir(handle.sftp, remoteProject)) {
                if (entry.directory || !isProjectOutputFile(entry.name, kind)) continue;
                handle.sftp.get(sftpPath(remoteProject, entry.name), new File(target, entry.name).getAbsolutePath());
            }
        } finally {
            handle.close();
        }
        remoteConnected = true;
        return target;
    }

    private boolean isProjectOutputFile(String name, String kind) {
        String lower = name.toLowerCase(Locale.ROOT);
        if ("partitura".equals(kind)) {
            return lower.endsWith("_партитура.xlsx") || lower.endsWith("_партитура.pdf") || lower.endsWith("_new.xml");
        }
        return lower.endsWith("_пресеты.xlsx") || lower.endsWith("_пресеты.pdf");
    }

    private void syncProjectToRemote(File dir) {
        if (!remoteMode || dir == null || !dir.exists()) return;
        Executors.newSingleThreadExecutor().execute(() -> {
            try {
                requireProjectXml(dir);
                if ("yandex_disk".equals(cloudProvider)) {
                    yandexUploadProject(dir, null);
                } else {
                    SftpHandle handle = openCloud();
                    String remoteProject = sftpPath(remoteBasePath, dir.getName());
                    uploadRemoteDirAtomic(handle.sftp, dir, remoteProject, null);
                    handle.close();
                    mirrorProjectToRemoteCache(dir);
                }
                remoteConnected = true;
            } catch (Exception ignored) {
                remoteConnected = false;
            }
        });
    }

    private void saveProjectToRemoteWithToast(File dir) {
        showLoadingScreen("Загружаю проект в облако...");
        Executors.newSingleThreadExecutor().execute(() -> {
            boolean ok = false;
            String error = "";
            try {
                requireProjectXml(dir);
                if ("yandex_disk".equals(cloudProvider)) {
                    yandexUploadProject(dir, (done, total, name) -> updateLoading("Загружаю " + done + "/" + total + ": " + name));
                } else {
                    SftpHandle handle = openCloud();
                    String remoteProject = sftpPath(remoteBasePath, dir.getName());
                    uploadRemoteDirAtomic(handle.sftp, dir, remoteProject, (done, total, name) -> updateLoading("Загружаю " + done + "/" + total + ": " + name));
                    handle.close();
                    mirrorProjectToRemoteCache(dir);
                }
                ok = true;
            } catch (Exception exc) {
                error = exc.getMessage();
                remoteConnected = false;
            }
            boolean result = ok;
            String message = error;
            runOnUiThread(() -> {
                Toast.makeText(this, result ? "Сохранено в облако" : "Не удалось сохранить в облако: " + message, Toast.LENGTH_LONG).show();
                if (projectModeDir != null) showProjectModeScreen(projectModeDir, projectModeCloud);
                else showProjectListScreen("projects", !projectBrowserCloud);
            });
        });
    }

    private void saveProjectToRemoteWithConfirm(File dir) {
        File cachedRemoteProject = new File(remoteCacheRootDir(), dir.getName());
        if (cachedRemoteProject.exists()) {
            new AlertDialog.Builder(this)
                    .setTitle("Такой проект уже есть в облаке")
                    .setMessage("Заменить?")
                    .setPositiveButton("Заменить", (d, w) -> saveProjectToRemoteWithToast(dir))
                    .setNegativeButton("Отмена", null)
                    .show();
        } else {
            saveProjectToRemoteWithToast(dir);
        }
    }

    private void saveProjectToLocal(File dir) {
        try {
            File target = new File(localPassportsRootDir(), dir.getName());
            if (target.exists()) {
                new AlertDialog.Builder(this)
                        .setTitle("Такой проект уже есть локально")
                        .setMessage("Заменить?")
                        .setPositiveButton("Заменить", (d, w) -> {
                            downloadProjectToLocal(dir, target, true);
                        })
                        .setNegativeButton("Отмена", null)
                        .show();
            } else {
                downloadProjectToLocal(dir, target, false);
            }
        } catch (Exception e) {
            Toast.makeText(this, "Локально: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void downloadProjectToLocal(File sourceDir, File target, boolean replace) {
        showLoadingScreen("Скачиваю проект...");
        Executors.newSingleThreadExecutor().execute(() -> {
            boolean ok = false;
            String error = "";
            try {
                if (projectBrowserCloud) {
                    if (replace) deleteRecursive(target);
                    if ("yandex_disk".equals(cloudProvider)) {
                        yandexDownloadProject(sourceDir.getName(), target, (done, total, name) -> updateLoading("Скачиваю " + done + "/" + total + ": " + name));
                    } else {
                        SftpHandle handle = openCloud();
                        downloadRemoteDir(handle.sftp, sftpPath(remoteBasePath, sourceDir.getName()), target, (done, total, name) -> updateLoading("Скачиваю " + done + "/" + total + ": " + name));
                        handle.close();
                    }
                } else {
                    if (replace) deleteRecursive(target);
                    copyRecursive(sourceDir, target);
                }
                ok = true;
            } catch (Exception exc) {
                error = exc.getMessage();
            }
            boolean result = ok;
            String message = error;
            runOnUiThread(() -> {
                Toast.makeText(this, result ? "Сохранено локально" : "Не удалось скачать: " + message, Toast.LENGTH_LONG).show();
                if (result) {
                    projectBrowserCloud = false;
                    remoteMode = false;
                    showProjectListScreen("projects");
                } else {
                    showProjectModeScreen(sourceDir, projectBrowserCloud);
                }
            });
        });
    }

    private void deleteRemoteProject(String projectName) {
        if (!remoteMode || projectName == null) return;
        Executors.newSingleThreadExecutor().execute(() -> {
            try {
                if ("yandex_disk".equals(cloudProvider)) {
                    yandexDeleteProject(projectName);
                } else {
                    SftpHandle handle = openCloud();
                    removeRemoteTree(handle.sftp, sftpPath(remoteBasePath, projectName));
                    handle.close();
                }
            } catch (Exception ignored) {
            }
        });
    }

    private static class CloudEntry {
        final String name;
        final boolean directory;
        CloudEntry(String name, boolean directory) {
            this.name = name;
            this.directory = directory;
        }
    }

    private interface TransferProgress {
        void onProgress(int done, int total, String name);
    }

    private static class RemoteFile {
        final String remotePath;
        final String relativePath;
        RemoteFile(String remotePath, String relativePath) {
            this.remotePath = remotePath;
            this.relativePath = relativePath;
        }
    }

    private static class SftpHandle {
        final Session session;
        final ChannelSftp sftp;
        SftpHandle(Session session, ChannelSftp sftp) {
            this.session = session;
            this.sftp = sftp;
        }
        void close() {
            try { sftp.disconnect(); } catch (Exception ignored) {}
            try { session.disconnect(); } catch (Exception ignored) {}
        }
    }

    private String readHttp(HttpURLConnection conn) throws Exception {
        InputStream stream = conn.getResponseCode() >= 400 ? conn.getErrorStream() : conn.getInputStream();
        if (stream == null) return "";
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        copy(stream, out);
        return out.toString("UTF-8");
    }

    private JSONObject yandexJson(String method, String endpoint, String[][] params) throws Exception {
        StringBuilder url = new StringBuilder("https://cloud-api.yandex.net/v1/disk/").append(endpoint);
        if (params != null && params.length > 0) {
            url.append("?");
            for (int i = 0; i < params.length; i++) {
                if (i > 0) url.append("&");
                url.append(URLEncoder.encode(params[i][0], "UTF-8")).append("=")
                        .append(URLEncoder.encode(params[i][1], "UTF-8"));
            }
        }
        HttpURLConnection conn = (HttpURLConnection) new URL(url.toString()).openConnection();
        conn.setRequestMethod(method);
        conn.setRequestProperty("Authorization", "OAuth " + yandexAccessToken);
        int status = conn.getResponseCode();
        String body = readHttp(conn);
        if (status != 200 && status != 201 && status != 202 && status != 204 && status != 409) {
            throw new Exception("Yandex HTTP " + status + ": " + body);
        }
        return body.isEmpty() ? new JSONObject() : new JSONObject(body);
    }

    private void yandexEnsureDir(String diskPath) throws Exception {
        String clean = diskPath.replace("app:/", "");
        String current = "app:";
        for (String part : clean.split("/")) {
            if (part.isEmpty()) continue;
            current = current + "/" + part;
            yandexJson("PUT", "resources", new String[][]{{"path", current}});
        }
    }

    private String yandexProjectPath(String projectName) {
        return "app:/" + REMOTE_ROOT_NAME + "/" + projectName;
    }

    private JSONArray yandexList(String diskPath) throws Exception {
        JSONObject json = yandexJson("GET", "resources", new String[][]{{"path", diskPath}, {"limit", "1000"}});
        JSONObject embedded = json.optJSONObject("_embedded");
        return embedded == null ? new JSONArray() : embedded.optJSONArray("items") == null ? new JSONArray() : embedded.optJSONArray("items");
    }

    private String yandexHref(String endpoint, String diskPath, boolean overwrite) throws Exception {
        JSONObject json = yandexJson("GET", endpoint, overwrite
                ? new String[][]{{"path", diskPath}, {"overwrite", "true"}}
                : new String[][]{{"path", diskPath}});
        String href = json.optString("href", "");
        if (href.isEmpty()) throw new Exception("Yandex не вернул href");
        return href;
    }

    private void yandexPutFile(String href, File file) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(href).openConnection();
        conn.setRequestMethod("PUT");
        conn.setDoOutput(true);
        copy(new FileInputStream(file), conn.getOutputStream());
        int status = conn.getResponseCode();
        if (status < 200 || status >= 300) throw new Exception("Upload HTTP " + status + ": " + readHttp(conn));
    }

    private void yandexGetFile(String href, File file) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(href).openConnection();
        int status = conn.getResponseCode();
        if (status < 200 || status >= 300) throw new Exception("Download HTTP " + status + ": " + readHttp(conn));
        File parent = file.getParentFile();
        if (parent != null && !parent.exists()) parent.mkdirs();
        copy(conn.getInputStream(), file);
    }

    private void yandexUploadProject(File dir, TransferProgress progress) throws Exception {
        requireProjectXml(dir);
        String remoteProject = yandexProjectPath(dir.getName());
        yandexEnsureDir(remoteProject);
        ArrayList<File> files = localProjectFiles(dir);
        for (int i = 0; i < files.size(); i++) {
            File file = files.get(i);
            String relative = dir.toPath().relativize(file.toPath()).toString().replace("\\", "/");
            if (progress != null) progress.onProgress(i + 1, files.size(), relative);
            if (relative.contains("/")) {
                yandexEnsureDir(remoteProject + "/" + relative.substring(0, relative.lastIndexOf('/')));
            }
            yandexPutFile(yandexHref("resources/upload", remoteProject + "/" + relative, true), file);
        }
        mirrorProjectToRemoteCache(dir);
    }

    private void yandexDownloadProjectIndex(File localRoot) throws Exception {
        deleteRecursive(localRoot);
        if (!localRoot.exists()) localRoot.mkdirs();
        yandexEnsureDir("app:/" + REMOTE_ROOT_NAME);
        JSONArray projects = yandexList("app:/" + REMOTE_ROOT_NAME);
        for (int i = 0; i < projects.length(); i++) {
            JSONObject project = projects.optJSONObject(i);
            if (project == null || !"dir".equals(project.optString("type"))) continue;
            String name = project.optString("name", "");
            String path = project.optString("path", yandexProjectPath(name));
            boolean hasXml = false;
            JSONArray entries = yandexList(path);
            for (int e = 0; e < entries.length(); e++) {
                JSONObject item = entries.optJSONObject(e);
                if (item != null && "file".equals(item.optString("type")) && item.optString("name").toLowerCase(Locale.ROOT).endsWith(".xml")) {
                    hasXml = true;
                }
            }
            if (!hasXml) continue;
            File localProject = new File(localRoot, name);
            if (!localProject.exists()) localProject.mkdirs();
        }
    }

    private ArrayList<RemoteFile> yandexCollectFiles(String diskPath, String relative) throws Exception {
        ArrayList<RemoteFile> files = new ArrayList<>();
        JSONArray entries = yandexList(diskPath);
        for (int i = 0; i < entries.length(); i++) {
            JSONObject item = entries.optJSONObject(i);
            if (item == null) continue;
            String name = item.optString("name", "");
            String itemPath = item.optString("path", diskPath + "/" + name);
            String childRelative = relative.isEmpty() ? name : relative + "/" + name;
            if ("dir".equals(item.optString("type"))) files.addAll(yandexCollectFiles(itemPath, childRelative));
            else if ("file".equals(item.optString("type"))) files.add(new RemoteFile(itemPath, childRelative));
        }
        return files;
    }

    private void yandexDownloadProject(String projectName, File target, TransferProgress progress) throws Exception {
        ArrayList<RemoteFile> files = yandexCollectFiles(yandexProjectPath(projectName), "");
        File temp = new File(target.getParentFile(), "." + target.getName() + ".download");
        deleteRecursive(temp);
        if (!temp.mkdirs()) throw new Exception("Не могу создать " + temp.getAbsolutePath());
        try {
            for (int i = 0; i < files.size(); i++) {
                RemoteFile file = files.get(i);
                if (progress != null) progress.onProgress(i + 1, files.size(), file.relativePath);
                yandexGetFile(yandexHref("resources/download", file.remotePath, false), new File(temp, file.relativePath));
            }
            if (findProjectXml(temp) == null) throw new Exception("В скачанном проекте нет XML");
            deleteRecursive(target);
            if (!temp.renameTo(target)) throw new Exception("Не могу заменить проект");
        } catch (Exception e) {
            deleteRecursive(temp);
            throw e;
        }
    }

    private void yandexDeleteProject(String projectName) throws Exception {
        yandexJson("DELETE", "resources", new String[][]{{"path", yandexProjectPath(projectName)}, {"permanently", "true"}});
    }

    private SftpHandle openCloud() throws Exception {
        JSch jsch = new JSch();
        Session session = jsch.getSession(cloudUser, cloudUrl, cloudPort);
        session.setPassword(cloudPassword);
        java.util.Properties config = new java.util.Properties();
        config.put("StrictHostKeyChecking", "no");
        session.setConfig(config);
        session.connect(15000);
        ChannelSftp sftp = (ChannelSftp) session.openChannel("sftp");
        sftp.connect(15000);
        if (remoteBasePath == null || remoteBasePath.trim().isEmpty()) remoteBasePath = REMOTE_ROOT_NAME;
        ensureRemoteDir(sftp, remoteBasePath);
        return new SftpHandle(session, sftp);
    }

    private String sftpPath(String a, String b) {
        String base = a == null ? "" : a.replace("\\", "/");
        String child = b == null ? "" : b.replace("\\", "/");
        if (base.endsWith("/")) base = base.substring(0, base.length() - 1);
        while (child.startsWith("/")) child = child.substring(1);
        return base.isEmpty() ? child : base + "/" + child;
    }

    private boolean remoteExists(ChannelSftp sftp, String path) {
        try {
            sftp.stat(path);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private boolean remoteIsDir(ChannelSftp sftp, String path) {
        try {
            return sftp.stat(path).isDir();
        } catch (Exception e) {
            return false;
        }
    }

    private void ensureRemoteDir(ChannelSftp sftp, String path) throws Exception {
        String clean = path.replace("\\", "/");
        String current = clean.startsWith("/") ? "/" : "";
        for (String part : clean.split("/")) {
            if (part.isEmpty()) continue;
            current = sftpPath(current, part);
            try {
                sftp.mkdir(current);
            } catch (SftpException ignored) {
            }
        }
    }

    private void removeRemoteTree(ChannelSftp sftp, String path) {
        try {
            if (!remoteExists(sftp, path)) return;
            if (remoteIsDir(sftp, path)) {
                Vector<ChannelSftp.LsEntry> entries = sftp.ls(path);
                for (ChannelSftp.LsEntry entry : entries) {
                    String name = entry.getFilename();
                    if (".".equals(name) || "..".equals(name)) continue;
                    removeRemoteTree(sftp, sftpPath(path, name));
                }
                sftp.rmdir(path);
            } else {
                sftp.rm(path);
            }
        } catch (Exception ignored) {
        }
    }

    private ArrayList<CloudEntry> listRemoteDir(ChannelSftp sftp, String remote) throws Exception {
        ArrayList<CloudEntry> result = new ArrayList<>();
        Vector<ChannelSftp.LsEntry> entries = sftp.ls(remote);
        for (ChannelSftp.LsEntry entry : entries) {
            String name = entry.getFilename();
            if (".".equals(name) || "..".equals(name)) continue;
            result.add(new CloudEntry(name, entry.getAttrs().isDir()));
        }
        return result;
    }

    private ArrayList<RemoteFile> collectRemoteFiles(ChannelSftp sftp, String remote, String relative) throws Exception {
        ArrayList<RemoteFile> files = new ArrayList<>();
        for (CloudEntry entry : listRemoteDir(sftp, remote)) {
            String childRemote = sftpPath(remote, entry.name);
            String childRelative = relative.isEmpty() ? entry.name : relative + "/" + entry.name;
            if (entry.directory) files.addAll(collectRemoteFiles(sftp, childRemote, childRelative));
            else files.add(new RemoteFile(childRemote, childRelative));
        }
        return files;
    }

    private ArrayList<File> localProjectFiles(File root) {
        ArrayList<File> files = new ArrayList<>();
        collectLocalFiles(root, files);
        files.sort(Comparator
                .comparingInt((File file) -> file.getName().toLowerCase(Locale.ROOT).endsWith(".xml") ? 0 : 1)
                .thenComparing(file -> root.toPath().relativize(file.toPath()).toString().toLowerCase(Locale.ROOT)));
        return files;
    }

    private void collectLocalFiles(File file, ArrayList<File> files) {
        if (file.isFile()) {
            files.add(file);
            return;
        }
        File[] children = file.listFiles();
        if (children == null) return;
        for (File child : children) collectLocalFiles(child, files);
    }

    private void uploadRemoteDirAtomic(ChannelSftp sftp, File local, String remote, TransferProgress progress) throws Exception {
        requireProjectXml(local);
        String temp = remote + ".upload";
        removeRemoteTree(sftp, temp);
        ensureRemoteDir(sftp, temp);
        try {
            ArrayList<File> files = localProjectFiles(local);
            for (int i = 0; i < files.size(); i++) {
                File file = files.get(i);
                String relative = local.toPath().relativize(file.toPath()).toString().replace("\\", "/");
                if (progress != null) progress.onProgress(i + 1, files.size(), relative);
                String parent = temp;
                String[] parts = relative.split("/");
                for (int p = 0; p < parts.length - 1; p++) {
                    parent = sftpPath(parent, parts[p]);
                    ensureRemoteDir(sftp, parent);
                }
                sftp.put(file.getAbsolutePath(), sftpPath(parent, parts[parts.length - 1]));
            }
            removeRemoteTree(sftp, remote);
            sftp.rename(temp, remote);
        } catch (Exception e) {
            removeRemoteTree(sftp, temp);
            throw e;
        }
    }

    private void downloadRemoteDir(ChannelSftp sftp, String remote, File local, TransferProgress progress) throws Exception {
        ArrayList<RemoteFile> files = collectRemoteFiles(sftp, remote, "");
        File temp = new File(local.getParentFile(), "." + local.getName() + ".download");
        deleteRecursive(temp);
        if (!temp.mkdirs()) throw new Exception("Не могу создать " + temp.getAbsolutePath());
        try {
            for (int i = 0; i < files.size(); i++) {
                RemoteFile file = files.get(i);
                if (progress != null) progress.onProgress(i + 1, files.size(), file.relativePath);
                File target = new File(temp, file.relativePath);
                File parent = target.getParentFile();
                if (parent != null && !parent.exists()) parent.mkdirs();
                sftp.get(file.remotePath, target.getAbsolutePath());
            }
            if (findProjectXml(temp) == null) throw new Exception("В скачанном проекте нет XML");
            deleteRecursive(local);
            if (!temp.renameTo(local)) throw new Exception("Не могу заменить проект");
        } catch (Exception e) {
            deleteRecursive(temp);
            throw e;
        }
    }

    private void downloadRemoteProjectIndex(ChannelSftp sftp, String remoteRoot, File localRoot) throws Exception {
        if (!localRoot.exists()) localRoot.mkdirs();
        for (CloudEntry project : listRemoteDir(sftp, remoteRoot)) {
            if (!project.directory) continue;
            String remoteProject = sftpPath(remoteRoot, project.name);
            boolean hasXml = false;
            for (CloudEntry entry : listRemoteDir(sftp, remoteProject)) {
                if (!entry.directory && entry.name.toLowerCase(Locale.ROOT).endsWith(".xml")) hasXml = true;
            }
            if (!hasXml) continue;
            File localProject = new File(localRoot, project.name);
            if (!localProject.exists()) localProject.mkdirs();
        }
    }

    private void mirrorProjectToRemoteCache(File dir) throws Exception {
        File target = new File(remoteCacheRootDir(), dir.getName());
        if (target.equals(dir)) return;
        deleteRecursive(target);
        copyRecursive(dir, target);
    }

    private void loadProjectData(File xmlCopy, boolean newProject) throws Exception {
        items.clear();
        items.addAll(parsePresets(xmlCopy));

        LinkedHashMap<String, PresetItem> itemByKey = new LinkedHashMap<>();
        for (PresetItem item : items) itemByKey.put(rowKey(item.presetLabel, item.fixtureId), item);

        rows.clear();
        File table = passportTableFile();
        if (!newProject) {
            List<PassportRow> stateRows = readPassportState();
            List<PassportRow> xlsxRows = table.exists() ? Xlsx.readPassportRows(table) : new ArrayList<>();
            List<PassportRow> tableRows = mergeExistingRows(stateRows, xlsxRows);
            LinkedHashMap<String, Integer> seen = new LinkedHashMap<>();
            for (PassportRow row : tableRows) {
                PresetItem item = itemByKey.get(rowKey(row.presetLabel, row.fixtureId));
                if (item != null) row.presetNo = item.presetNo;
                if (row.presetNo == null || row.presetNo.isEmpty()) row.presetNo = row.presetLabel;
                String key = rowKey(row.presetLabel, row.fixtureId);
                int duplicateIndex = seen.containsKey(key) ? seen.get(key) + 1 : 1;
                seen.put(key, duplicateIndex);
                if (row.photoFile == null || !row.photoFile.exists()) {
                    row.photoFile = findPhotoForRow(row, duplicateIndex);
                }
                rows.add(row);
            }
        }

        LinkedHashSet<String> baseRowsPresent = new LinkedHashSet<>();
        for (PassportRow row : rows) baseRowsPresent.add(rowKey(row.presetLabel, row.fixtureId));

        for (PresetItem item : items) {
            String key = rowKey(item.presetLabel, item.fixtureId);
            if (!baseRowsPresent.contains(key)) {
                PassportRow row = new PassportRow(item.presetLabel, item.fixtureId, item.presetNo, findPhoto(item), "");
                rows.add(row);
                baseRowsPresent.add(key);
            }
        }

        if (rows.isEmpty()) {
            for (PresetItem item : items) {
                rows.add(new PassportRow(item.presetLabel, item.fixtureId, item.presetNo, findPhoto(item), ""));
            }
        }
    }

    private List<PassportRow> mergeExistingRows(List<PassportRow> stateRows, List<PassportRow> xlsxRows) {
        if (stateRows == null || stateRows.isEmpty()) return xlsxRows == null ? new ArrayList<>() : xlsxRows;
        if (xlsxRows == null || xlsxRows.isEmpty()) return stateRows;

        LinkedHashMap<String, PassportRow> xlsxByOccurrence = new LinkedHashMap<>();
        LinkedHashMap<String, Integer> xlsxCounts = new LinkedHashMap<>();
        for (PassportRow row : xlsxRows) {
            String baseKey = rowKey(row.presetLabel, row.fixtureId);
            int index = xlsxCounts.containsKey(baseKey) ? xlsxCounts.get(baseKey) : 0;
            xlsxCounts.put(baseKey, index + 1);
            xlsxByOccurrence.put(baseKey + "\n" + index, row);
        }

        LinkedHashSet<String> usedXlsxRows = new LinkedHashSet<>();
        LinkedHashMap<String, Integer> stateCounts = new LinkedHashMap<>();
        ArrayList<PassportRow> merged = new ArrayList<>();
        for (PassportRow row : stateRows) {
            String baseKey = rowKey(row.presetLabel, row.fixtureId);
            int index = stateCounts.containsKey(baseKey) ? stateCounts.get(baseKey) : 0;
            stateCounts.put(baseKey, index + 1);
            String occurrence = baseKey + "\n" + index;
            PassportRow copy = new PassportRow(row.presetLabel, row.fixtureId, row.presetNo, row.photoFile, row.description);
            PassportRow xlsxRow = xlsxByOccurrence.get(occurrence);
            if (xlsxRow != null) {
                copy.description = xlsxRow.description;
                usedXlsxRows.add(occurrence);
            }
            merged.add(copy);
        }

        xlsxCounts.clear();
        for (PassportRow row : xlsxRows) {
            String baseKey = rowKey(row.presetLabel, row.fixtureId);
            int index = xlsxCounts.containsKey(baseKey) ? xlsxCounts.get(baseKey) : 0;
            xlsxCounts.put(baseKey, index + 1);
            String occurrence = baseKey + "\n" + index;
            if (!usedXlsxRows.contains(occurrence)) {
                merged.add(row);
            }
        }
        return merged;
    }

    private void toggleRun() {
        running = !running;
        startButton.setText(running ? "Стоп" : "Начать");
        photoButton.setEnabled(running);
        skipButton.setEnabled(running);
        if (!running) exportPresets(false);
    }

    private void showCurrent() {
        if (rows.isEmpty()) {
            currentText.setText("");
            return;
        }
        if (index >= rows.size()) index = rows.size() - 1;
        if (index < 0) index = 0;
        PassportRow row = rows.get(index);
        currentText.setText((index + 1) + "/" + rows.size() + "  Пресет: " + row.presetLabel + "  Прибор: " + row.fixtureId);
        loadingDescription = true;
        descriptionEdit.setText(row.description);
        loadingDescription = false;
        if (tempPhoto != null && tempPhoto.exists() && tempPhotoIndex == index) {
            capturedPreview.setImageBitmap(loadPreviewBitmap(tempPhoto));
            capturedPreview.setVisibility(View.VISIBLE);
            if (emptyPhotoBox != null) emptyPhotoBox.setVisibility(View.GONE);
            if (deletePhotoButton != null) deletePhotoButton.setVisibility(View.GONE);
        } else if (row.photoFile != null && row.photoFile.exists()) {
            capturedPreview.setImageBitmap(loadPreviewBitmap(row.photoFile));
            capturedPreview.setVisibility(View.VISIBLE);
            if (emptyPhotoBox != null) emptyPhotoBox.setVisibility(View.GONE);
            if (deletePhotoButton != null) deletePhotoButton.setVisibility(View.VISIBLE);
        } else {
            capturedPreview.setImageDrawable(null);
            capturedPreview.setVisibility(View.GONE);
            if (emptyPhotoBox != null) emptyPhotoBox.setVisibility(View.VISIBLE);
            if (deletePhotoButton != null) deletePhotoButton.setVisibility(View.GONE);
        }
        refreshActionButtons();
        listView.setItemChecked(index, true);
        if (adapter != null) adapter.notifyDataSetChanged();
        listView.smoothScrollToPosition(index);
    }

    private void saveDescription() {
        if (loadingDescription || rows.isEmpty() || descriptionEdit == null) return;
        rows.get(index).description = descriptionEdit.getText().toString().trim();
        refreshOne(index);
    }

    private void takePhoto() {
        openCameraFromCurrent();
    }

    private void capturePhoto() {
        if (takingPhoto) return;
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.CAMERA}, REQ_CAMERA_PERMISSION);
            return;
        }
        if (imageCapture == null) {
            ensureCamera();
            Toast.makeText(this, "Камера ещё запускается", Toast.LENGTH_SHORT).show();
            return;
        }
        takingPhoto = true;
        if (photoButton != null) photoButton.setEnabled(false);
        if (skipButton != null) skipButton.setEnabled(false);
        tempPhoto = new File(getCacheDir(), "shot_" + System.currentTimeMillis() + ".jpg");
        tempPhotoIndex = index;
        ImageCapture.OutputFileOptions options = new ImageCapture.OutputFileOptions.Builder(tempPhoto).build();
        if (cameraPreview.getDisplay() != null) {
            imageCapture.setTargetRotation(cameraPreview.getDisplay().getRotation());
        } else {
            imageCapture.setTargetRotation(Surface.ROTATION_0);
        }
        try {
            imageCapture.takePicture(
                    options,
                    cameraExecutor,
                    new ImageCapture.OnImageSavedCallback() {
                        @Override
                        public void onImageSaved(@NonNull ImageCapture.OutputFileResults outputFileResults) {
                            saveCapturedPhotoAndReturn();
                        }

                        @Override
                        public void onError(@NonNull ImageCaptureException exception) {
                            runOnUiThread(() -> {
                                takingPhoto = false;
                                if (photoButton != null) photoButton.setEnabled(true);
                                if (skipButton != null) skipButton.setEnabled(true);
                                Toast.makeText(MainActivity.this, "Камера: " + exception.getMessage(), Toast.LENGTH_LONG).show();
                            });
                        }
                    }
            );
        } catch (Exception e) {
            takingPhoto = false;
            if (photoButton != null) photoButton.setEnabled(true);
            if (skipButton != null) skipButton.setEnabled(true);
            Toast.makeText(this, "Камера: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private Bitmap loadPreviewBitmap(File file) {
        try {
            if (file == null || !file.exists()) return null;
            int targetWidth = capturedPreview != null && capturedPreview.getWidth() > 0 ? capturedPreview.getWidth() : 1280;
            int targetHeight = capturedPreview != null && capturedPreview.getHeight() > 0 ? capturedPreview.getHeight() : 720;
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(file.getAbsolutePath(), bounds);
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null;

            int sample = 1;
            while ((bounds.outWidth / sample) > targetWidth * 2 || (bounds.outHeight / sample) > targetHeight * 2) {
                sample *= 2;
            }

            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inSampleSize = Math.max(1, sample);
            options.inPreferredConfig = Bitmap.Config.RGB_565;
            return BitmapFactory.decodeFile(file.getAbsolutePath(), options);
        } catch (OutOfMemoryError | RuntimeException e) {
            Toast.makeText(this, "Фото сохранено, но превью не открылось", Toast.LENGTH_LONG).show();
            return null;
        }
    }

    private void saveCapturedPhotoAndReturn() {
        runOnUiThread(() -> {
            takingPhoto = false;
            if (tempPhoto == null || !tempPhoto.exists()) {
                Toast.makeText(this, "Фото не сохранилось", Toast.LENGTH_LONG).show();
            }
            showPresetWorkspace();
        });
    }

    private void writePassportNow() throws Exception {
        if (projectDir == null) return;
        File out = passportTableFile();
        File tmp = new File(projectDir, safe(showTitle) + "_пресеты.tmp.xlsx");
        File pdfOut = new File(projectDir, safe(showTitle) + "_пресеты.pdf");
        File pdfTmp = new File(projectDir, safe(showTitle) + "_пресеты.tmp.pdf");
        synchronized (passportWriteLock) {
            writePassportState();
            Xlsx.writePassport(tmp, displayTitle(showTitle), rows);
            writePassportPdf(pdfTmp, displayTitle(showTitle), rows);
            if (out.exists() && !out.delete()) {
                throw new Exception("Не могу заменить " + out.getName());
            }
            if (!tmp.renameTo(out)) {
                copy(new FileInputStream(tmp), out);
                tmp.delete();
            }
            if (pdfOut.exists() && !pdfOut.delete()) {
                throw new Exception("Не могу заменить " + pdfOut.getName());
            }
            if (!pdfTmp.renameTo(pdfOut)) {
                copy(new FileInputStream(pdfTmp), pdfOut);
                pdfTmp.delete();
            }
        }
    }

    private File passportStateFile() {
        return new File(projectDir, "passport_state.json");
    }

    private void writePassportState() throws Exception {
        if (projectDir == null) return;
        JSONArray array = new JSONArray();
        for (PassportRow row : rows) {
            JSONObject item = new JSONObject();
            item.put("presetLabel", row.presetLabel == null ? "" : row.presetLabel);
            item.put("fixtureId", row.fixtureId == null ? "" : row.fixtureId);
            item.put("presetNo", row.presetNo == null ? "" : row.presetNo);
            item.put("photoName", row.photoFile == null ? JSONObject.NULL : row.photoFile.getName());
            item.put("description", row.description == null ? "" : row.description);
            array.put(item);
        }
        JSONObject root = new JSONObject();
        root.put("rows", array);
        try (FileOutputStream out = new FileOutputStream(passportStateFile())) {
            out.write(root.toString(2).getBytes(StandardCharsets.UTF_8));
        }
    }

    private List<PassportRow> readPassportState() {
        ArrayList<PassportRow> result = new ArrayList<>();
        if (projectDir == null) return result;
        File stateFile = passportStateFile();
        if (!stateFile.exists()) return result;
        try {
            String raw = new String(Xlsx.readAll(new FileInputStream(stateFile)), StandardCharsets.UTF_8);
            JSONArray array = new JSONObject(raw).optJSONArray("rows");
            if (array == null) return result;
            for (int i = 0; i < array.length(); i++) {
                JSONObject item = array.optJSONObject(i);
                if (item == null) continue;
                String photoName = item.optString("photoName", "");
                File photo = null;
                if (!photoName.isEmpty() && photosDir != null) {
                    File candidate = new File(photosDir, photoName);
                    if (candidate.exists()) photo = candidate;
                }
                result.add(new PassportRow(
                        item.optString("presetLabel", ""),
                        item.optString("fixtureId", ""),
                        item.optString("presetNo", ""),
                        photo,
                        item.optString("description", "")
                ));
            }
        } catch (Exception ignored) {
        }
        return result;
    }

    private void savePassportQuietly() {
        if (projectDir == null || cameraExecutor == null) return;
        cameraExecutor.execute(() -> {
            try {
                writePassportNow();
            } catch (Exception ignored) {
            }
        });
    }

    private void writePassportPdf(File out, String title, List<PassportRow> passportRows) throws Exception {
        PdfDocument pdf = new PdfDocument();
        Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
        text.setColor(Color.BLACK);
        text.setTextSize(10);
        Paint bold = new Paint(text);
        bold.setFakeBoldText(true);
        Paint line = new Paint(Paint.ANTI_ALIAS_FLAG);
        line.setColor(0xffc8c8c8);
        line.setStrokeWidth(1);
        line.setStyle(Paint.Style.STROKE);

        int pageWidth = 842;
        int pageHeight = 595;
        int margin = 34;
        int rowHeight = 116;
        int headerHeight = 54;
        int rowsPerPage = Math.max(1, (pageHeight - margin * 2 - headerHeight) / rowHeight);
        int pageCount = Math.max(1, (int) Math.ceil(passportRows.size() / (double) rowsPerPage));
        int colPreset = margin;
        int presetWidth = 176;
        int colFixture = colPreset + presetWidth;
        int fixtureWidth = 62;
        int colPhoto = colFixture + fixtureWidth;
        int photoWidth = 198;
        int colDesc = colPhoto + photoWidth;
        int descWidth = 255;
        int tableWidth = presetWidth + fixtureWidth + photoWidth + descWidth;

        for (int page = 0; page < pageCount; page++) {
            PdfDocument.PageInfo info = new PdfDocument.PageInfo.Builder(pageWidth, pageHeight, page + 1).create();
            PdfDocument.Page pdfPage = pdf.startPage(info);
            Canvas canvas = pdfPage.getCanvas();
            canvas.drawColor(Color.WHITE);

            text.setTextSize(10);
            bold.setTextSize(15);
            canvas.drawText(title, margin, margin + 16, bold);
            bold.setTextSize(10);
            int headerTop = margin + 28;
            int headerBottom = headerTop + 24;
            canvas.drawRect(colPreset, headerTop, colPreset + presetWidth, headerBottom, line);
            canvas.drawRect(colFixture, headerTop, colFixture + fixtureWidth, headerBottom, line);
            canvas.drawRect(colPhoto, headerTop, colPhoto + photoWidth, headerBottom, line);
            canvas.drawRect(colDesc, headerTop, colDesc + descWidth, headerBottom, line);
            drawPdfLine(canvas, "Пресет", colPreset, headerTop + 16, presetWidth, bold, true);
            drawPdfLine(canvas, "Прибор", colFixture, headerTop + 16, fixtureWidth, bold, true);
            drawPdfLine(canvas, "Фото", colPhoto, headerTop + 16, photoWidth, bold, true);
            drawPdfLine(canvas, "Описание", colDesc, headerTop + 16, descWidth, bold, true);

            for (int i = 0; i < rowsPerPage; i++) {
                int rowIndex = page * rowsPerPage + i;
                if (rowIndex >= passportRows.size()) break;
                PassportRow row = passportRows.get(rowIndex);
                int top = margin + headerHeight + i * rowHeight;
                int bottom = top + rowHeight;
                int base = top + 18;
                int groupStart = rowIndex;
                while (groupStart > 0 && samePassportPdfGroup(passportRows.get(groupStart), passportRows.get(groupStart - 1))) groupStart--;
                int groupEnd = rowIndex;
                while (groupEnd + 1 < passportRows.size() && samePassportPdfGroup(passportRows.get(groupEnd), passportRows.get(groupEnd + 1))) groupEnd++;
                int pageStart = page * rowsPerPage;
                int pageEnd = Math.min(passportRows.size() - 1, pageStart + rowsPerPage - 1);
                boolean firstInPageGroup = rowIndex == Math.max(groupStart, pageStart);
                if (firstInPageGroup) {
                    int spanRows = Math.min(groupEnd, pageEnd) - rowIndex + 1;
                    canvas.drawRect(colPreset, top, colPreset + presetWidth, top + spanRows * rowHeight, line);
                    canvas.drawRect(colFixture, top, colFixture + fixtureWidth, top + spanRows * rowHeight, line);
                    drawWrappedTextCentered(canvas, row.presetLabel, colPreset + 4, top, presetWidth - 8, spanRows * rowHeight, text, 6);
                    drawPdfLine(canvas, row.fixtureId, colFixture + 3, base, fixtureWidth - 6, text, true);
                }
                canvas.drawRect(colPhoto, top, colPhoto + photoWidth, bottom, line);
                canvas.drawRect(colDesc, top, colDesc + descWidth, bottom, line);
                drawWrappedText(canvas, row.description == null ? "" : row.description, colDesc + 4, base, descWidth - 8, text, 5);

                if (row.photoFile != null && row.photoFile.exists()) {
                    Bitmap bitmap = loadPdfBitmap(row.photoFile, 181, 108);
                    if (bitmap != null) {
                        Rect dst = fitRect(bitmap.getWidth(), bitmap.getHeight(), colPhoto + 8, top + 4, 181, 108);
                        canvas.drawBitmap(bitmap, null, dst, null);
                        bitmap.recycle();
                    }
                }
            }
            canvas.drawText((page + 1) + "/" + pageCount, pageWidth - margin - 36, pageHeight - 12, text);
            pdf.finishPage(pdfPage);
        }

        try (FileOutputStream output = new FileOutputStream(out)) {
            pdf.writeTo(output);
        } finally {
            pdf.close();
        }
    }

    private boolean samePassportPdfGroup(PassportRow a, PassportRow b) {
        if (a == null || b == null) return false;
        return cleanPdfText(a.presetLabel).equals(cleanPdfText(b.presetLabel)) && cleanPdfText(a.fixtureId).equals(cleanPdfText(b.fixtureId));
    }

    private String cleanPdfText(String value) {
        return value == null ? "" : value.trim();
    }

    private void drawWrappedText(Canvas canvas, String value, int x, int y, int width, Paint paint, int maxLines) {
        if (value == null) return;
        List<String> lines = wrappedLines(value, width, paint, maxLines);
        for (int i = 0; i < lines.size(); i++) {
            canvas.drawText(lines.get(i), x, y + i * 13, paint);
        }
    }

    private void drawWrappedTextCentered(Canvas canvas, String value, int x, int top, int width, int height, Paint paint, int maxLines) {
        if (value == null) return;
        List<String> lines = wrappedLines(value, width, paint, maxLines);
        if (lines.isEmpty()) return;
        int lineHeight = 13;
        Paint.FontMetrics metrics = paint.getFontMetrics();
        float textBlockHeight = (lines.size() - 1) * lineHeight + (metrics.descent - metrics.ascent);
        float firstBaseline = top + (height - textBlockHeight) / 2f - metrics.ascent;
        for (int i = 0; i < lines.size(); i++) {
            String lineText = lines.get(i);
            float dx = Math.max(0, (width - paint.measureText(lineText)) / 2f);
            canvas.drawText(lineText, x + dx, firstBaseline + i * lineHeight, paint);
        }
    }

    private List<String> wrappedLines(String value, int width, Paint paint, int maxLines) {
        ArrayList<String> lines = new ArrayList<>();
        if (value == null) return lines;
        String[] words = value.split("\\s+");
        StringBuilder lineText = new StringBuilder();
        for (String word : words) {
            if (word.isEmpty()) continue;
            String next = lineText.length() == 0 ? word : lineText + " " + word;
            if (paint.measureText(next) > width && lineText.length() > 0) {
                lines.add(lineText.toString());
                lineText = new StringBuilder(word);
                if (lines.size() >= maxLines) return lines;
            } else {
                lineText = new StringBuilder(next);
            }
        }
        if (lineText.length() > 0 && lines.size() < maxLines) {
            lines.add(lineText.toString());
        }
        return lines;
    }

    private Bitmap loadPdfBitmap(File file, int maxWidth, int maxHeight) {
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(file.getAbsolutePath(), bounds);
        int sample = 1;
        while ((bounds.outWidth / sample) > maxWidth * 2 || (bounds.outHeight / sample) > maxHeight * 2) {
            sample *= 2;
        }
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inSampleSize = Math.max(1, sample);
        options.inPreferredConfig = Bitmap.Config.RGB_565;
        return BitmapFactory.decodeFile(file.getAbsolutePath(), options);
    }

    private Rect fitRect(int sourceWidth, int sourceHeight, int x, int y, int maxWidth, int maxHeight) {
        float scale = Math.min(maxWidth / (float) sourceWidth, maxHeight / (float) sourceHeight);
        int width = Math.max(1, Math.round(sourceWidth * scale));
        int height = Math.max(1, Math.round(sourceHeight * scale));
        int left = x + (maxWidth - width) / 2;
        int top = y + (maxHeight - height) / 2;
        return new Rect(left, top, left + width, top + height);
    }

    private void ensureCamera() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.CAMERA}, REQ_CAMERA_PERMISSION);
            return;
        }
        if (cameraPreview == null) return;
        imageCapture = null;
        ListenableFuture<ProcessCameraProvider> cameraProviderFuture = ProcessCameraProvider.getInstance(this);
        cameraProviderFuture.addListener(() -> {
            try {
                ProcessCameraProvider cameraProvider = cameraProviderFuture.get();
                Preview preview = new Preview.Builder().build();
                preview.setSurfaceProvider(cameraPreview.getSurfaceProvider());
                imageCapture = new ImageCapture.Builder()
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                        .setJpegQuality(82)
                        .setTargetResolution(new Size(1280, 720))
                        .build();
                cameraProvider.unbindAll();
                boundCamera = cameraProvider.bindToLifecycle(
                        this,
                        new CameraSelector.Builder().requireLensFacing(lensFacing).build(),
                        preview,
                        imageCapture
                );
            } catch (Exception e) {
                Toast.makeText(this, "Камера: " + e.getMessage(), Toast.LENGTH_LONG).show();
            }
        }, ContextCompat.getMainExecutor(this));
    }

    private void stopCamera() {
        try {
            imageCapture = null;
            boundCamera = null;
            ListenableFuture<ProcessCameraProvider> cameraProviderFuture = ProcessCameraProvider.getInstance(this);
            cameraProviderFuture.addListener(() -> {
                try {
                    cameraProviderFuture.get().unbindAll();
                } catch (Exception ignored) {
                }
            }, ContextCompat.getMainExecutor(this));
        } catch (Exception ignored) {
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQ_CAMERA_PERMISSION && grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            ensureCamera();
        }
    }

    private void usePhoto() {
        if (tempPhoto == null || !tempPhoto.exists() || tempPhotoIndex != index) return;
        saveDescription();
        try {
            PassportRow row = rows.get(index);
            File target = photoTargetForRow(row);
            if (row.photoFile != null && row.photoFile.exists()) row.photoFile.delete();
            if (target.exists()) target.delete();
            copy(new FileInputStream(tempPhoto), target);
            row.photoFile = target;
            row.skipped = false;
            tempPhoto.delete();
            tempPhoto = null;
            tempPhotoIndex = -1;
            refreshOne(index);
            int savedIndex = index;
            index = nextTodoFrom(savedIndex);
            showCurrent();
            savePassportQuietly();
        } catch (Exception e) {
            Toast.makeText(this, "Фото: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void importPhotoForCurrent() {
        if (rows.isEmpty()) return;
        saveDescription();
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("image/*");
        startActivityForResult(intent, REQ_IMPORT_PHOTO);
    }

    private void importPhotoFromUri(Uri uri) {
        if (uri == null || rows.isEmpty()) return;
        try {
            PassportRow row = rows.get(index);
            File target = photoTargetForRow(row);
            if (row.photoFile != null && row.photoFile.exists()) row.photoFile.delete();
            if (target.exists()) target.delete();
            copy(getContentResolver().openInputStream(uri), target);
            row.photoFile = target;
            row.skipped = false;
            refreshOne(index);
            showCurrent();
            savePassportQuietly();
        } catch (Exception e) {
            Toast.makeText(this, "Фото: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void addPhotoRowAfterCurrent() {
        if (rows.isEmpty()) return;
        saveDescription();
        PassportRow current = rows.get(index);
        PassportRow extra = new PassportRow(current.presetLabel, current.fixtureId, current.presetNo, null, "");
        rows.add(index + 1, extra);
        index++;
        refreshList();
        showCurrent();
        savePassportQuietly();
    }

    private void confirmDeletePhoto() {
        if (rows.isEmpty()) return;
        new AlertDialog.Builder(this)
                .setTitle("Удалить фото?")
                .setPositiveButton("Удалить", (dialog, which) -> {
                    PassportRow row = rows.get(index);
                    if (row.photoFile != null && row.photoFile.exists()) row.photoFile.delete();
                    row.photoFile = null;
                    refreshOne(index);
                    showCurrent();
                    savePassportQuietly();
                })
                .setNegativeButton("Отмена", null)
                .show();
    }

    private void confirmDeleteRow(int position) {
        if (position < 0 || position >= rows.size()) return;
        new AlertDialog.Builder(this)
                .setTitle("Удалить запись?")
                .setMessage(rows.get(position).presetLabel + " / " + rows.get(position).fixtureId)
                .setPositiveButton("Удалить", (dialog, which) -> {
                    PassportRow row = rows.remove(position);
                    if (row.photoFile != null && row.photoFile.exists()) row.photoFile.delete();
                    if (index >= rows.size()) index = rows.size() - 1;
                    if (index < 0) index = 0;
                    refreshList();
                    showCurrent();
                    savePassportQuietly();
                })
                .setNegativeButton("Отмена", null)
                .show();
    }

    private void skipItem() {
        saveDescription();
        PassportRow row = rows.get(index);
        row.skipped = true;
        refreshOne(index);
        index = nextTodo();
        showCurrent();
    }

    private void deleteCurrent() {
        if (rows.isEmpty()) return;
        PassportRow row = rows.get(index);
        if (row.photoFile != null && row.photoFile.exists()) row.photoFile.delete();
        row.photoFile = null;
        row.description = "";
        row.skipped = false;
        refreshOne(index);
        showCurrent();
    }

    private int nextTodo() {
        return nextTodoFrom(index);
    }

    private int nextTodoFrom(int startIndex) {
        for (int offset = 1; offset <= rows.size(); offset++) {
            int candidate = (startIndex + offset) % rows.size();
            PassportRow row = rows.get(candidate);
            if ((row.photoFile == null || !row.photoFile.exists()) && !row.skipped) return candidate;
        }
        return startIndex;
    }

    private void refreshList() {
        listLabels.clear();
        for (int i = 0; i < rows.size(); i++) listLabels.add(labelFor(i));
        adapter.notifyDataSetChanged();
    }

    private void refreshOne(int i) {
        if (i >= 0 && i < listLabels.size()) {
            listLabels.set(i, labelFor(i));
            adapter.notifyDataSetChanged();
        }
    }

    private String labelFor(int i) {
        PassportRow row = rows.get(i);
        String state = row.photoFile != null && row.photoFile.exists() ? "фото" : (row.skipped ? "пропуск" : "");
        return row.presetLabel + " | " + row.fixtureId + " | " + state + " " + row.description;
    }

    private void exportPresets(boolean toast) {
        if (projectDir == null) return;
        saveDescription();
        try {
            File out = passportTableFile();
            writePassportNow();
            if (toast) {
                Toast.makeText(this, "Сохранено: " + out.getAbsolutePath(), Toast.LENGTH_LONG).show();
                showProjectFilesScreen(projectDir, "presets");
            }
        } catch (Exception e) {
            Toast.makeText(this, "Экспорт: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void exportPartitura() {
        if (projectDir == null) return;
        try {
            ensurePartituraFields();
            File xml = findProjectXml(projectDir);
            if (xml == null) throw new Exception("XML не найден");
            List<PartRow> parts = parsePartitura(xml);
            File out = new File(projectDir, safe(showTitle) + "_партитура.xlsx");
            File pdf = new File(projectDir, safe(showTitle) + "_партитура.pdf");
            ArrayList<PartituraField> fields = enabledPartituraFields();
            Xlsx.writePartitura(out, displayTitle(showTitle), parts, fields);
            writePartituraPdf(pdf, displayTitle(showTitle), parts, fields);
            Toast.makeText(this, "Партитура: " + out.getAbsolutePath(), Toast.LENGTH_LONG).show();
        } catch (Exception e) {
            Toast.makeText(this, "Партитура: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void createPartituraFromSettings() {
        try {
            ensurePartituraFields();
            if (selectedPartituraProjectDir == null) throw new Exception("Выбери проект");
            ArrayList<PartituraField> fields = enabledPartituraFields();
            if (fields.isEmpty()) throw new Exception("Включи хотя бы одно поле");
            File xml = findProjectXml(selectedPartituraProjectDir);
            if (xml == null) throw new Exception("XML не найден");
            String title = projectTitleFromDir(selectedPartituraProjectDir);
            String documentTitle = displayTitle(title);
            List<PartRow> parts = parsePartitura(xml);
            File out = new File(selectedPartituraProjectDir, safe(title) + "_партитура.xlsx");
            File pdf = new File(selectedPartituraProjectDir, safe(title) + "_партитура.pdf");
            Xlsx.writePartitura(out, documentTitle, parts, fields);
            writePartituraPdf(pdf, documentTitle, parts, fields);
            Toast.makeText(this, "Партитура создана: " + out.getName(), Toast.LENGTH_LONG).show();
            showProjectFilesScreen(selectedPartituraProjectDir, "partitura");
        } catch (Exception e) {
            Toast.makeText(this, "Партитура: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void savePartituraShowXmlFromSettings() {
        try {
            if (selectedPartituraProjectDir == null) throw new Exception("Выбери проект");
            File xml = findProjectXml(selectedPartituraProjectDir);
            if (xml == null) throw new Exception("XML не найден");
            String title = projectTitleFromDir(selectedPartituraProjectDir);
            File output = new File(selectedPartituraProjectDir, safe(title) + "_new.xml");
            copy(new FileInputStream(xml), output);
            Toast.makeText(this, "Создан show-файл: " + output.getName(), Toast.LENGTH_LONG).show();
            showProjectFilesScreen(selectedPartituraProjectDir, "partitura");
        } catch (Exception e) {
            Toast.makeText(this, "Show XML: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private ArrayList<PartituraField> enabledPartituraFields() {
        ArrayList<PartituraField> fields = new ArrayList<>();
        for (PartituraField field : partituraFields) {
            if (field.enabled) fields.add(field);
        }
        return fields;
    }

    private void writePartituraPdf(File out, String title, List<PartRow> rows, List<PartituraField> fields) throws Exception {
        PdfDocument pdf = new PdfDocument();
        Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
        text.setColor(Color.BLACK);
        text.setTextSize(8);
        Paint bold = new Paint(text);
        bold.setFakeBoldText(true);
        Paint line = new Paint(Paint.ANTI_ALIAS_FLAG);
        line.setColor(0xffc8c8c8);
        line.setStrokeWidth(1);
        line.setStyle(Paint.Style.STROKE);

        int pageWidth = 595;
        int pageHeight = 842;
        int margin = 22;
        int headerHeight = 58;
        int rowHeight = 44;
        int rowsPerPage = Math.max(1, (pageHeight - margin * 2 - headerHeight) / rowHeight);
        int pageCount = Math.max(1, (int) Math.ceil(rows.size() / (double) rowsPerPage));
        int tableWidth = pageWidth - margin * 2;
        int[] widths = pdfColumnWidths(fields, tableWidth);

        for (int page = 0; page < pageCount; page++) {
            PdfDocument.PageInfo info = new PdfDocument.PageInfo.Builder(pageWidth, pageHeight, page + 1).create();
            PdfDocument.Page pdfPage = pdf.startPage(info);
            Canvas canvas = pdfPage.getCanvas();
            canvas.drawColor(Color.WHITE);
            bold.setTextSize(14);
            canvas.drawText(title, margin, margin + 14, bold);

            bold.setTextSize(8);
            int headerTop = margin + 30;
            int x = margin;
            for (int i = 0; i < fields.size(); i++) {
                canvas.drawRect(x, headerTop, x + widths[i], headerTop + 22, line);
                drawCellText(canvas, fields.get(i).title, x + 3, headerTop + 14, widths[i] - 6, bold, true, 1);
                x += widths[i];
            }

            for (int i = 0; i < rowsPerPage; i++) {
                int rowIndex = page * rowsPerPage + i;
                if (rowIndex >= rows.size()) break;
                PartRow row = rows.get(rowIndex);
                int top = margin + headerHeight + i * rowHeight;
                x = margin;
                for (int c = 0; c < fields.size(); c++) {
                    PartituraField field = fields.get(c);
                    canvas.drawRect(x, top, x + widths[c], top + rowHeight, line);
                    boolean left = "name".equals(field.id) || "info".equals(field.id) || "command".equals(field.id);
                    drawCellText(canvas, row.value(field.id), x + 3, top + 12, widths[c] - 6, text, !left, 3);
                    x += widths[c];
                }
            }
            canvas.drawText((page + 1) + "/" + pageCount, pageWidth - margin - 28, pageHeight - 10, text);
            pdf.finishPage(pdfPage);
        }

        try (FileOutputStream output = new FileOutputStream(out)) {
            pdf.writeTo(output);
        } finally {
            pdf.close();
        }
    }

    private int[] pdfColumnWidths(List<PartituraField> fields, int tableWidth) {
        int[] weights = new int[fields.size()];
        int total = 0;
        for (int i = 0; i < fields.size(); i++) {
            String id = fields.get(i).id;
            int w = ("name".equals(id) || "info".equals(id)) ? 4 : ("command".equals(id) ? 3 : 1);
            weights[i] = w;
            total += w;
        }
        int[] widths = new int[fields.size()];
        int used = 0;
        for (int i = 0; i < fields.size(); i++) {
            widths[i] = Math.max(32, Math.round(tableWidth * (weights[i] / (float) total)));
            used += widths[i];
        }
        if (widths.length > 0) widths[widths.length - 1] += tableWidth - used;
        return widths;
    }

    private void drawCellText(Canvas canvas, String value, int x, int y, int width, Paint paint, boolean center, int maxLines) {
        if (value == null) value = "";
        String[] words = value.split("\\s+");
        StringBuilder lineText = new StringBuilder();
        int lineNo = 0;
        for (String word : words) {
            String next = lineText.length() == 0 ? word : lineText + " " + word;
            if (paint.measureText(next) > width && lineText.length() > 0) {
                drawPdfLine(canvas, lineText.toString(), x, y + lineNo * 11, width, paint, center);
                lineNo++;
                lineText = new StringBuilder(word);
                if (lineNo >= maxLines) return;
            } else {
                lineText = new StringBuilder(next);
            }
        }
        if (lineText.length() > 0 && lineNo < maxLines) {
            drawPdfLine(canvas, lineText.toString(), x, y + lineNo * 11, width, paint, center);
        }
    }

    private void drawPdfLine(Canvas canvas, String value, int x, int y, int width, Paint paint, boolean center) {
        float dx = center ? Math.max(0, (width - paint.measureText(value)) / 2f) : 0;
        canvas.drawText(value, x + dx, y, paint);
    }

    private void loadExistingTableIfPresent() {
        try {
            File xml = findProjectXml(projectDir);
            if (xml != null) loadProjectData(xml, false);
        } catch (Exception ignored) {
        }
    }

    private List<PresetItem> parsePresets(File xml) throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        Document doc = factory.newDocumentBuilder().parse(xml);
        NodeList cueDatas = doc.getElementsByTagNameNS("*", "CueData");
        LinkedHashMap<String, LinkedHashSet<String>> map = new LinkedHashMap<>();
        LinkedHashMap<String, String> names = new LinkedHashMap<>();

        for (int i = 0; i < cueDatas.getLength(); i++) {
            Element cueData = (Element) cueDatas.item(i);
            Element channel = firstChild(cueData, "Channel");
            Element preset = firstChild(cueData, "Preset");
            if (channel == null || preset == null) continue;
            String fixture = channel.getAttribute("fixture_id");
            if (fixture.isEmpty()) fixture = channel.getAttribute("channel_id");
            if (fixture.isEmpty()) continue;
            String name = preset.getAttribute("name");
            String no = presetNo(preset);
            String key = no + "\n" + name;
            names.put(key, name);
            if (!map.containsKey(key)) map.put(key, new LinkedHashSet<>());
            map.get(key).add(fixture);
        }

        ArrayList<PresetItem> result = new ArrayList<>();
        for (String key : map.keySet()) {
            for (String fixture : map.get(key)) {
                result.add(new PresetItem(names.get(key), fixture, key.split("\n", -1)[0]));
            }
        }
        return result;
    }

    private List<PartRow> parsePartitura(File xml) throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        Document doc = factory.newDocumentBuilder().parse(xml);
        NodeList cues = doc.getElementsByTagNameNS("*", "Cue");
        ArrayList<PartRow> rows = new ArrayList<>();
        for (int i = 0; i < cues.getLength(); i++) {
            Element cue = (Element) cues.item(i);
            Element number = firstChild(cue, "Number");
            if (number == null) continue;
            String cueNumber = cueNumber(number);
            Element triggerEl = firstChild(cue, "Trigger");
            String trigger = triggerEl == null ? "Go" : triggerEl.getAttribute("type");
            String triggerTime = triggerEl == null ? "" : triggerEl.getAttribute("data_f");
            String cueInfo = cueInfo(cue);
            String cueCommand = cueCommand(cue);
            NodeList parts = cue.getElementsByTagNameNS("*", "CuePart");
            for (int p = 0; p < parts.getLength(); p++) {
                Element part = (Element) parts.item(p);
                String partIndex = part.getAttribute("index");
                if (!partIndex.isEmpty() && !"0".equals(partIndex)) continue;
                String displayNumber = cueNumber;
                String name = part.hasAttribute("name") ? part.getAttribute("name") : "cue";
                String fade = part.hasAttribute("basic_fade") ? part.getAttribute("basic_fade") : "0";
                String downfade = part.hasAttribute("basic_downfade") ? part.getAttribute("basic_downfade") : "";
                String delay = part.hasAttribute("basic_delay") ? part.getAttribute("basic_delay") : "";
                String info = firstNonEmpty(cuePartInfo(part), cueInfo);
                String command = firstNonEmpty(cuePartCommand(part), cueCommand);
                rows.add(new PartRow(displayNumber, name, fade, downfade, delay, trigger, triggerTime, info, command));
            }
        }
        return rows;
    }

    private String cueInfo(Element cue) {
        Element infoItems = firstChild(cue, "InfoItems");
        if (infoItems != null) {
            Element info = firstChild(infoItems, "Info");
            if (info != null) return textOrAttrs(info);
        }
        Element info = firstChild(cue, "Info");
        return info == null ? "" : textOrAttrs(info);
    }

    private String cuePartInfo(Element part) {
        Element infoItems = firstChild(part, "InfoItems");
        if (infoItems != null) {
            Element info = firstChild(infoItems, "Info");
            if (info != null) return textOrAttrs(info);
        }
        Element info = firstChild(part, "Info");
        return info == null ? "" : textOrAttrs(info);
    }

    private String cueCommand(Element cue) {
        return commandFrom(cue);
    }

    private String cuePartCommand(Element part) {
        return commandFrom(part);
    }

    private String commandFrom(Element parent) {
        String[] attrNames = {"command", "cmd", "command_text", "Command", "Cmd"};
        for (String attr : attrNames) {
            if (parent.hasAttribute(attr) && !parent.getAttribute(attr).trim().isEmpty()) return parent.getAttribute(attr).trim();
        }
        String[] tags = {"CueCommand", "Command", "Cmd", "CLI", "CommandLine"};
        for (String tag : tags) {
            Element child = firstChild(parent, tag);
            if (child != null) return textOrAttrs(child);
        }
        return "";
    }

    private String textOrAttrs(Element element) {
        String text = element.getTextContent() == null ? "" : element.getTextContent().trim();
        if (!text.isEmpty()) return text;
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < element.getAttributes().getLength(); i++) {
            Node n = element.getAttributes().item(i);
            String value = n.getNodeValue();
            if (value != null && !value.trim().isEmpty()) {
                if (b.length() > 0) b.append(" ");
                b.append(value.trim());
            }
        }
        return b.toString();
    }

    private String firstNonEmpty(String first, String second) {
        return first != null && !first.trim().isEmpty() ? first : (second == null ? "" : second);
    }

    private String cueNumber(Element number) {
        String num = number.getAttribute("number");
        String sub = number.getAttribute("sub_number");
        if (sub == null || sub.isEmpty() || "0".equals(sub)) return num;
        try {
            int value = Integer.parseInt(sub);
            if (value % 100 == 0) return num + "." + (value / 100);
            if (value % 10 == 0) return num + "." + (value / 10);
        } catch (NumberFormatException ignored) {
        }
        return num + "." + sub;
    }

    private Element firstChild(Element parent, String localName) {
        NodeList children = parent.getChildNodes();
        for (int i = 0; i < children.getLength(); i++) {
            Node n = children.item(i);
            if (n instanceof Element && localName.equals(n.getLocalName())) return (Element) n;
        }
        return null;
    }

    private String presetNo(Element preset) {
        NodeList nos = preset.getElementsByTagNameNS("*", "No");
        ArrayList<String> parts = new ArrayList<>();
        for (int i = 0; i < nos.getLength(); i++) parts.add(nos.item(i).getTextContent().trim());
        return join(parts, ".");
    }

    private File findPhoto(PresetItem item) {
        File exact = new File(photosDir, item.fileStem() + ".jpg");
        if (exact.exists()) return exact;
        File legacy = new File(photosDir, safe(item.presetLabel + "_" + item.fixtureId) + ".jpg");
        return legacy.exists() ? legacy : null;
    }

    private File findPhotoForRow(PassportRow row, int duplicateIndex) {
        String stem = row.fileStem();
        String legacyStem = safe(row.presetLabel + "_" + row.fixtureId);
        ArrayList<String> stems = new ArrayList<>();
        stems.add(stem);
        if (!legacyStem.equals(stem)) stems.add(legacyStem);
        if (duplicateIndex > 1) {
            for (String candidate : stems) {
                File numbered = new File(photosDir, candidate + "_" + duplicateIndex + ".jpg");
                if (numbered.exists()) return numbered;
            }
        }
        for (String candidate : stems) {
            File exact = new File(photosDir, candidate + ".jpg");
            if (exact.exists()) return exact;
        }
        return null;
    }

    private File photoTargetForRow(PassportRow row) {
        int duplicateIndex = duplicateIndexForRow(index);
        String suffix = duplicateIndex > 1 ? "_" + duplicateIndex : "";
        return new File(photosDir, row.fileStem() + suffix + ".jpg");
    }

    private int duplicateIndexForRow(int rowIndex) {
        if (rowIndex < 0 || rowIndex >= rows.size()) return 1;
        PassportRow row = rows.get(rowIndex);
        int duplicate = 1;
        for (int i = 0; i < rowIndex; i++) {
            PassportRow other = rows.get(i);
            if (rowKey(other.presetLabel, other.fixtureId).equals(rowKey(row.presetLabel, row.fixtureId))) duplicate++;
        }
        return duplicate;
    }

    private File passportTableFile() {
        return new File(projectDir, safe(showTitle) + "_пресеты.xlsx");
    }

    private File findProjectXml(File dir) {
        if (dir == null || !dir.isDirectory()) return null;
        File preferred = new File(dir, safe(projectTitleFromDir(dir)) + ".xml");
        if (preferred.exists()) return preferred;
        File[] files = dir.listFiles(file -> file.isFile() && file.getName().toLowerCase(Locale.ROOT).endsWith(".xml"));
        return files != null && files.length > 0 ? files[0] : null;
    }

    private File requireProjectXml(File dir) throws Exception {
        File xml = findProjectXml(dir);
        if (xml == null) throw new Exception("в папке проекта нет XML");
        return xml;
    }

    private String projectTitleFromDir(File dir) {
        String folderName = dir.getName();
        return folderName.endsWith("_passport") ? folderName.substring(0, folderName.length() - "_passport".length()) : folderName;
    }

    private String displayTitle(String title) {
        return title == null ? "" : title.replace('_', ' ').trim();
    }

    private String rowKey(String presetLabel, String fixtureId) {
        return (presetLabel == null ? "" : presetLabel.trim()) + "\n" + (fixtureId == null ? "" : fixtureId.trim());
    }

    private void deleteRecursive(File file) {
        if (file == null || !file.exists()) return;
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) deleteRecursive(child);
            }
        }
        file.delete();
    }

    private void copyRecursive(File source, File target) throws Exception {
        if (source.isDirectory()) {
            if (!target.exists() && !target.mkdirs()) throw new Exception("Не могу создать " + target.getAbsolutePath());
            File[] children = source.listFiles();
            if (children != null) {
                for (File child : children) copyRecursive(child, new File(target, child.getName()));
            }
        } else {
            File parent = target.getParentFile();
            if (parent != null && !parent.exists()) parent.mkdirs();
            copy(new FileInputStream(source), target);
        }
    }

    private File uniquePhoto(String stem) {
        File file = new File(photosDir, stem + ".jpg");
        int counter = 2;
        while (file.exists()) file = new File(photosDir, stem + "_" + counter++ + ".jpg");
        return file;
    }

    private String getFileName(Uri uri) {
        String path = uri.getLastPathSegment();
        if (path == null) return "show.xml";
        int slash = path.lastIndexOf('/');
        return slash >= 0 ? path.substring(slash + 1) : path;
    }

    private String stripExtension(String name) {
        int dot = name.lastIndexOf('.');
        return dot > 0 ? name.substring(0, dot) : name;
    }

    static String safe(String s) {
        String out = s.replaceAll("[^0-9A-Za-zА-Яа-яЁё_.-]+", "_");
        return out.isEmpty() ? "show" : out;
    }

    static String esc(String s) {
        if (s == null) return "";
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
    }

    private void copy(InputStream in, File out) throws Exception {
        try (InputStream input = in; FileOutputStream output = new FileOutputStream(out)) {
            copy(input, output);
        }
    }

    private void copy(InputStream input, OutputStream output) throws Exception {
        try (InputStream in = input; OutputStream out = output) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        }
    }

    static String join(List<String> parts, String sep) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < parts.size(); i++) {
            if (i > 0) b.append(sep);
            b.append(parts.get(i));
        }
        return b.toString();
    }

    static class PresetItem {
        final String presetLabel;
        final String fixtureId;
        final String presetNo;
        PresetItem(String presetLabel, String fixtureId, String presetNo) {
            this.presetLabel = presetLabel;
            this.fixtureId = fixtureId;
            this.presetNo = presetNo;
        }
        String fileStem() {
            return safe(presetNo + "_" + fixtureId);
        }
    }

    static class PassportRow {
        String presetLabel;
        String fixtureId;
        String presetNo;
        File photoFile;
        String description;
        boolean skipped;
        PassportRow(String presetLabel, String fixtureId, String presetNo, File photoFile, String description) {
            this.presetLabel = presetLabel;
            this.fixtureId = fixtureId;
            this.presetNo = presetNo;
            this.photoFile = photoFile;
            this.description = description;
        }
        String fileStem() {
            return safe((presetNo == null || presetNo.isEmpty() ? presetLabel : presetNo) + "_" + fixtureId);
        }
    }

    static class PartituraField {
        final String id;
        final String title;
        boolean enabled;
        PartituraField(String id, String title, boolean enabled) {
            this.id = id;
            this.title = title;
            this.enabled = enabled;
        }
    }

    static class PartRow {
        String number, name, fade, downfade, delay, trigger, triggerTime, info, command;
        PartRow(String number, String name, String fade, String downfade, String delay, String trigger, String triggerTime, String info, String command) {
            this.number = number;
            this.name = name;
            this.fade = fade;
            this.downfade = downfade;
            this.delay = delay;
            this.trigger = trigger;
            this.triggerTime = triggerTime;
            this.info = info;
            this.command = command;
        }
        String value(String id) {
            if ("number".equals(id)) return number;
            if ("name".equals(id)) return name;
            if ("fade".equals(id)) return fade;
            if ("downfade".equals(id)) return downfade;
            if ("delay".equals(id)) return delay;
            if ("trigger".equals(id)) return trigger;
            if ("trigger_time".equals(id)) return triggerTime;
            if ("info".equals(id)) return info;
            if ("command".equals(id)) return command;
            return "";
        }
    }

    static class Xlsx {
        static void writePassport(File out, String title, List<PassportRow> rows) throws Exception {
            try (ZipOutputStream zip = new ZipOutputStream(new FileOutputStream(out))) {
                put(zip, "[Content_Types].xml", contentTypes(true));
                put(zip, "_rels/.rels", rels());
                put(zip, "xl/workbook.xml", workbook("Паспорт"));
                put(zip, "xl/_rels/workbook.xml.rels", workbookRels());
                put(zip, "xl/styles.xml", styles());
                put(zip, "xl/worksheets/sheet1.xml", passportSheet(title, rows));
                put(zip, "xl/worksheets/_rels/sheet1.xml.rels", sheetRels(rows));
                put(zip, "xl/drawings/drawing1.xml", drawing(rows));
                put(zip, "xl/drawings/_rels/drawing1.xml.rels", drawingRels(rows));
                int img = 1;
                for (PassportRow row : rows) {
                    if (row.photoFile != null && row.photoFile.exists()) {
                        put(zip, "xl/media/image" + img++ + ".jpg", xlsxImageBytes(row.photoFile));
                    }
                }
            }
        }

        static void writePartitura(File out, String title, List<PartRow> rows, List<PartituraField> fields) throws Exception {
            try (ZipOutputStream zip = new ZipOutputStream(new FileOutputStream(out))) {
                put(zip, "[Content_Types].xml", contentTypes(false));
                put(zip, "_rels/.rels", rels());
                put(zip, "xl/workbook.xml", workbook("Партитура"));
                put(zip, "xl/_rels/workbook.xml.rels", workbookRels());
                put(zip, "xl/styles.xml", styles());
                put(zip, "xl/worksheets/sheet1.xml", partSheet(title, rows, fields));
            }
        }

        static List<PassportRow> readPassportRows(File xlsx) throws Exception {
            ArrayList<PassportRow> result = new ArrayList<>();
            java.util.zip.ZipFile zip = new java.util.zip.ZipFile(xlsx);
            try {
                ArrayList<String> sharedStrings = readSharedStrings(zip);
                ZipEntry entry = zip.getEntry("xl/worksheets/sheet1.xml");
                if (entry == null) return result;
                String xml = new String(readAll(zip.getInputStream(entry)), StandardCharsets.UTF_8);
                String[] rowChunks = xml.split("<row ");
                String lastPreset = "";
                String lastFixture = "";
                for (String chunk : rowChunks) {
                    String rowNoText = attr(chunk, "r");
                    if (rowNoText.isEmpty()) continue;
                    int rowNo;
                    try {
                        rowNo = Integer.parseInt(rowNoText);
                    } catch (NumberFormatException e) {
                        continue;
                    }
                    if (rowNo < 3) continue;

                    LinkedHashMap<String, String> cells = new LinkedHashMap<>();
                    String[] cellChunks = chunk.split("<c ");
                    for (String cell : cellChunks) {
                        String ref = attr(cell, "r");
                        if (ref.isEmpty()) continue;
                        cells.put(columnLetters(ref), cellValue(cell, sharedStrings));
                    }

                    String preset = cells.containsKey("A") ? cells.get("A").trim() : "";
                    String fixture = cells.containsKey("B") ? cells.get("B").trim() : "";
                    String description = cells.containsKey("D") ? cells.get("D") : "";
                    if (preset.isEmpty()) preset = lastPreset;
                    if (fixture.isEmpty()) fixture = lastFixture;
                    if (preset.isEmpty() && fixture.isEmpty() && description.trim().isEmpty()) continue;
                    lastPreset = preset;
                    lastFixture = fixture;
                    result.add(new PassportRow(preset, fixture, "", null, description));
                }
            } finally {
                zip.close();
            }
            return result;
        }

        static ArrayList<String> readSharedStrings(java.util.zip.ZipFile zip) throws Exception {
            ArrayList<String> result = new ArrayList<>();
            ZipEntry entry = zip.getEntry("xl/sharedStrings.xml");
            if (entry == null) return result;
            String xml = new String(readAll(zip.getInputStream(entry)), StandardCharsets.UTF_8);
            String[] chunks = xml.split("<si");
            for (String chunk : chunks) {
                if (!chunk.contains("</si>")) continue;
                result.add(unesc(collectTextNodes(chunk)));
            }
            return result;
        }

        static String cellValue(String cell, List<String> sharedStrings) {
            String type = attr(cell, "t");
            if ("inlineStr".equals(type)) return unesc(collectTextNodes(cell));
            int vStart = cell.indexOf("<v>");
            int vEnd = cell.indexOf("</v>");
            if (vStart >= 0 && vEnd > vStart) {
                String raw = cell.substring(vStart + 3, vEnd);
                if ("s".equals(type)) {
                    try {
                        int i = Integer.parseInt(raw.trim());
                        return i >= 0 && i < sharedStrings.size() ? sharedStrings.get(i) : "";
                    } catch (NumberFormatException ignored) {
                    }
                }
                return unesc(raw);
            }
            return "";
        }

        static String collectTextNodes(String xml) {
            StringBuilder b = new StringBuilder();
            int pos = 0;
            while (true) {
                int start = xml.indexOf("<t", pos);
                if (start < 0) break;
                start = xml.indexOf(">", start);
                if (start < 0) break;
                int end = xml.indexOf("</t>", start);
                if (end < 0) break;
                b.append(xml, start + 1, end);
                pos = end + 4;
            }
            return b.toString();
        }

        static String attr(String xml, String name) {
            String key = name + "=\"";
            int start = xml.indexOf(key);
            if (start < 0) return "";
            start += key.length();
            int end = xml.indexOf("\"", start);
            return end > start ? xml.substring(start, end) : "";
        }

        static String columnLetters(String ref) {
            StringBuilder b = new StringBuilder();
            for (int i = 0; i < ref.length(); i++) {
                char c = ref.charAt(i);
                if (c >= 'A' && c <= 'Z') b.append(c);
            }
            return b.toString();
        }

        static String passportSheet(String title, List<PassportRow> rows) {
            StringBuilder b = new StringBuilder();
            b.append(sheetOpen()).append("<sheetData>");
            b.append(row(1, cell("A1", title, 1)))
                    .append(row(2, cell("A2", "Пресет", 2) + cell("B2", "Прибор", 2) + cell("C2", "Фото", 2) + cell("D2", "Описание", 2)));
            int r = 3;
            for (int i = 0; i < rows.size(); i++) {
                PassportRow row = rows.get(i);
                boolean sameAsPrevious = i > 0 && sameGroup(row, rows.get(i - 1));
                b.append("<row r=\"").append(r).append("\" ht=\"138\" customHeight=\"1\">")
                        .append(cell("A" + r, sameAsPrevious ? "" : row.presetLabel, 3))
                        .append(cell("B" + r, sameAsPrevious ? "" : row.fixtureId, 3))
                        .append(cell("C" + r, "", 3))
                        .append(cell("D" + r, row.description, 3))
                        .append("</row>");
                r++;
            }
            ArrayList<String> merges = new ArrayList<>();
            merges.add("A1:D1");
            int start = 0;
            while (start < rows.size()) {
                int end = start;
                while (end + 1 < rows.size() && sameGroup(rows.get(start), rows.get(end + 1))) end++;
                if (end > start) {
                    merges.add("A" + (start + 3) + ":A" + (end + 3));
                    merges.add("B" + (start + 3) + ":B" + (end + 3));
                }
                start = end + 1;
            }
            b.append("</sheetData><mergeCells count=\"").append(merges.size()).append("\">");
            for (String merge : merges) b.append("<mergeCell ref=\"").append(merge).append("\"/>");
            b.append("</mergeCells><drawing r:id=\"rId1\"/></worksheet>");
            return b.toString();
        }

        static boolean sameGroup(PassportRow a, PassportRow b) {
            if (a == null || b == null) return false;
            return safeText(a.presetLabel).equals(safeText(b.presetLabel)) && safeText(a.fixtureId).equals(safeText(b.fixtureId));
        }

        static String safeText(String value) {
            return value == null ? "" : value.trim();
        }

        static String partSheet(String title, List<PartRow> rows, List<PartituraField> fields) {
            StringBuilder b = new StringBuilder();
            b.append(partSheetOpen(fields)).append("<sheetData>");
            b.append(row(1, cell("A1", title, 1)));
            StringBuilder header = new StringBuilder();
            for (int i = 0; i < fields.size(); i++) {
                header.append(cell(colName(i + 1) + "2", fields.get(i).title, 2));
            }
            b.append(row(2, header.toString()));
            int r = 3;
            for (PartRow row : rows) {
                b.append("<row r=\"").append(r).append("\">");
                for (int i = 0; i < fields.size(); i++) {
                    PartituraField field = fields.get(i);
                    int style = ("name".equals(field.id) || "info".equals(field.id)) ? 4 : 3;
                    b.append(cell(colName(i + 1) + r, row.value(field.id), style));
                }
                b.append("</row>");
                r++;
            }
            String lastCol = colName(Math.max(1, fields.size()));
            b.append("</sheetData><mergeCells count=\"1\"><mergeCell ref=\"A1:").append(lastCol).append("1\"/></mergeCells></worksheet>");
            return b.toString();
        }

        static String partSheetOpen(List<PartituraField> fields) {
            StringBuilder b = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheetViews><sheetView workbookViewId=\"0\"/></sheetViews><cols>");
            for (int i = 0; i < fields.size(); i++) {
                String id = fields.get(i).id;
                int width;
                if ("number".equals(id)) width = 12;
                else if ("name".equals(id)) width = 48;
                else if ("trigger".equals(id)) width = 13;
                else if ("trigger_time".equals(id)) width = 15;
                else if ("fade".equals(id) || "delay".equals(id)) width = 10;
                else if ("downfade".equals(id)) width = 12;
                else if ("info".equals(id)) width = 54;
                else if ("command".equals(id)) width = 32;
                else width = 18;
                b.append("<col min=\"").append(i + 1).append("\" max=\"").append(i + 1).append("\" width=\"").append(width).append("\" customWidth=\"1\"/>");
            }
            return b.append("</cols>").toString();
        }

        static String colName(int oneBased) {
            StringBuilder b = new StringBuilder();
            int n = oneBased;
            while (n > 0) {
                n--;
                b.insert(0, (char) ('A' + (n % 26)));
                n /= 26;
            }
            return b.toString();
        }

        static String drawing(List<PassportRow> rows) {
            StringBuilder b = new StringBuilder();
            b.append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><xdr:wsDr xmlns:xdr=\"http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">");
            int img = 1;
            for (int i = 0; i < rows.size(); i++) {
                PassportRow row = rows.get(i);
                if (row.photoFile == null || !row.photoFile.exists()) continue;
                int excelRowZero = i + 2;
                b.append("<xdr:twoCellAnchor editAs=\"oneCell\">")
                        .append("<xdr:from><xdr:col>2</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>").append(excelRowZero).append("</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>")
                        .append("<xdr:to><xdr:col>3</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>").append(excelRowZero + 1).append("</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>")
                        .append("<xdr:pic><xdr:nvPicPr><xdr:cNvPr id=\"").append(img).append("\" name=\"Image ").append(img).append("\"/><xdr:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></xdr:cNvPicPr></xdr:nvPicPr>")
                        .append("<xdr:blipFill><a:blip r:embed=\"rId").append(img).append("\"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>")
                        .append("<xdr:spPr><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:twoCellAnchor>");
                img++;
            }
            return b.append("</xdr:wsDr>").toString();
        }

        static String drawingRels(List<PassportRow> rows) {
            StringBuilder b = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">");
            int img = 1;
            for (PassportRow row : rows) {
                if (row.photoFile != null && row.photoFile.exists()) {
                    b.append("<Relationship Id=\"rId").append(img).append("\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/image").append(img).append(".jpg\"/>");
                    img++;
                }
            }
            return b.append("</Relationships>").toString();
        }

        static String sheetRels(List<PassportRow> rows) {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing\" Target=\"../drawings/drawing1.xml\"/></Relationships>";
        }

        static String sheetOpen() {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheetViews><sheetView workbookViewId=\"0\"/></sheetViews><cols><col min=\"1\" max=\"1\" width=\"38\" customWidth=\"1\"/><col min=\"2\" max=\"2\" width=\"12\" customWidth=\"1\"/><col min=\"3\" max=\"3\" width=\"42\" customWidth=\"1\"/><col min=\"4\" max=\"4\" width=\"34\" customWidth=\"1\"/></cols>";
        }

        static String cell(String ref, String text) {
            return cell(ref, text, 0);
        }

        static String cell(String ref, String text, int style) {
            String styleAttr = style > 0 ? " s=\"" + style + "\"" : "";
            return "<c r=\"" + ref + "\"" + styleAttr + " t=\"inlineStr\"><is><t>" + esc(text) + "</t></is></c>";
        }

        static String row(int r, String cells) {
            return "<row r=\"" + r + "\">" + cells + "</row>";
        }

        static String contentTypes(boolean drawings) {
            String s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>";
            if (drawings) s += "<Override PartName=\"/xl/drawings/drawing1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawing+xml\"/>";
            return s + "</Types>";
        }

        static String rels() {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>";
        }

        static String workbook(String sheet) {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"" + esc(sheet) + "\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>";
        }

        static String workbookRels() {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>";
        }

        static String styles() {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
                    + "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
                    + "<fonts count=\"3\">"
                    + "<font><sz val=\"11\"/><name val=\"Arial\"/></font>"
                    + "<font><b/><sz val=\"16\"/><name val=\"Arial\"/></font>"
                    + "<font><b/><sz val=\"11\"/><name val=\"Arial\"/></font>"
                    + "</fonts>"
                    + "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>"
                    + "<borders count=\"2\"><border/><border><left style=\"thin\"/><right style=\"thin\"/><top style=\"thin\"/><bottom style=\"thin\"/></border></borders>"
                    + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
                    + "<cellXfs count=\"5\">"
                    + "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>"
                    + "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyAlignment=\"1\"><alignment horizontal=\"center\" vertical=\"center\"/></xf>"
                    + "<xf numFmtId=\"0\" fontId=\"2\" fillId=\"0\" borderId=\"1\" xfId=\"0\" applyFont=\"1\" applyBorder=\"1\" applyAlignment=\"1\"><alignment horizontal=\"center\" vertical=\"center\" wrapText=\"1\"/></xf>"
                    + "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"1\" xfId=\"0\" applyBorder=\"1\" applyAlignment=\"1\"><alignment horizontal=\"center\" vertical=\"center\" wrapText=\"1\"/></xf>"
                    + "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"1\" xfId=\"0\" applyBorder=\"1\" applyAlignment=\"1\"><alignment horizontal=\"left\" vertical=\"center\" wrapText=\"1\"/></xf>"
                    + "</cellXfs>"
                    + "</styleSheet>";
        }

        static void put(ZipOutputStream zip, String name, String text) throws Exception {
            put(zip, name, text.getBytes(StandardCharsets.UTF_8));
        }

        static void put(ZipOutputStream zip, String name, byte[] bytes) throws Exception {
            zip.putNextEntry(new ZipEntry(name));
            zip.write(bytes);
            zip.closeEntry();
        }

        static byte[] readBytes(File file) throws Exception {
            return readAll(new FileInputStream(file));
        }

        static byte[] xlsxImageBytes(File file) throws Exception {
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(file.getAbsolutePath(), bounds);
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return readBytes(file);

            int sample = 1;
            while ((bounds.outWidth / sample) > 1280 || (bounds.outHeight / sample) > 720) {
                sample *= 2;
            }

            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inSampleSize = Math.max(1, sample);
            options.inPreferredConfig = Bitmap.Config.RGB_565;
            Bitmap bitmap = BitmapFactory.decodeFile(file.getAbsolutePath(), options);
            if (bitmap == null) return readBytes(file);

            try (ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                bitmap.compress(Bitmap.CompressFormat.JPEG, 78, out);
                bitmap.recycle();
                return out.toByteArray();
            }
        }

        static byte[] readAll(InputStream input) throws Exception {
            try (InputStream in = input; ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                return out.toByteArray();
            }
        }

        static String unesc(String s) {
            return s.replace("&quot;", "\"").replace("&gt;", ">").replace("&lt;", "<").replace("&amp;", "&");
        }
    }
}
