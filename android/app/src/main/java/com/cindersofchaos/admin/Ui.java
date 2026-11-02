package com.cindersofchaos.admin;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.InputType;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.core.content.ContextCompat;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.textfield.TextInputEditText;
import com.google.android.material.textfield.TextInputLayout;

/**
 * The view builders of every screen, all made in code. A forge on the night shift: one warm neutral ramp (the same as
 * the desktop app, desktop/src/theme.rs), text-coloured headings, ember only for the main action and the dot of a
 * running server, gold only for the selected tab. Spacing on a 4 dp grid, type 12, 13, 14, 16, 20, one icon size (20).
 */
final class Ui {
    final Context c;
    /** Neutral ramp: window, card, raised control, hairline, strong hairline, input well. */
    final int bg;
    final int surface;
    final int raised;
    final int edge;
    final int edgeStrong;
    final int input;
    /** Text roles: primary, secondary, muted. */
    final int text;
    final int text2;
    final int muted;
    /** The one accent: ember (main action, live dot), its deeper button fill and the light text on it. */
    final int ember;
    final int emberDeep;
    final int onEmber;
    /** Gold marks only the selected tab (res/color/nav_item.xml). */
    final int gold;
    /** Status: ok, warning, error; the dark fill and rim of a destructive button. */
    final int ok;
    final int warn;
    final int error;
    final int errorDeep;
    final int errorEdge;
    final int onError;

    static final Typeface MEDIUM = Typeface.create("sans-serif-medium", Typeface.NORMAL);

    Ui(Context c) {
        this.c = c;
        bg = col(R.color.bg);
        surface = col(R.color.surface);
        raised = col(R.color.raised);
        edge = col(R.color.edge);
        edgeStrong = col(R.color.edge_strong);
        input = col(R.color.input);
        text = col(R.color.text);
        text2 = col(R.color.text2);
        muted = col(R.color.muted);
        ember = col(R.color.ember);
        emberDeep = col(R.color.ember_deep);
        onEmber = col(R.color.on_ember);
        gold = col(R.color.gold);
        ok = col(R.color.ok);
        warn = col(R.color.warn);
        error = col(R.color.error);
        errorDeep = col(R.color.error_deep);
        errorEdge = col(R.color.error_edge);
        onError = col(R.color.on_error);
    }

    private int col(int id) {
        return ContextCompat.getColor(c, id);
    }

    int dp(float v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, c.getResources().getDisplayMetrics()));
    }

    // ------------------------------------------------------------------------------------------------ layout

    LinearLayout column() {
        LinearLayout l = new LinearLayout(c);
        l.setOrientation(LinearLayout.VERTICAL);
        return l;
    }

    LinearLayout row() {
        LinearLayout l = new LinearLayout(c);
        l.setOrientation(LinearLayout.HORIZONTAL);
        l.setGravity(Gravity.CENTER_VERTICAL);
        return l;
    }

    /** The page body: a column with the screen margins. */
    LinearLayout page() {
        LinearLayout l = column();
        l.setPadding(dp(16), dp(12), dp(16), dp(24));
        return l;
    }

    static LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    static LinearLayout.LayoutParams weight(float w) {
        return new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, w);
    }

    LinearLayout.LayoutParams gap(int topDp) {
        LinearLayout.LayoutParams p = matchWrap();
        p.topMargin = dp(topDp);
        return p;
    }

    /** Adds the views to a row with equal widths and a small gap between them. */
    LinearLayout evenRow(View... kids) {
        LinearLayout r = row();
        for (int i = 0; i < kids.length; i++) {
            LinearLayout.LayoutParams p = weight(1f);
            if (i > 0) {
                p.leftMargin = dp(8);
            }
            r.addView(kids[i], p);
        }
        return r;
    }

    // ------------------------------------------------------------------------------------------------ cards

    /** A dark card with a hairline rim; returns the card, its content is {@link #body(MaterialCardView)}. */
    MaterialCardView card() {
        MaterialCardView card = new MaterialCardView(c);
        card.setCardBackgroundColor(surface);
        card.setStrokeColor(edge);
        card.setStrokeWidth(dp(1));
        card.setRadius(dp(12));
        card.setCardElevation(0);
        LinearLayout body = column();
        body.setPadding(dp(16), dp(16), dp(16), dp(16));
        card.addView(body, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        return card;
    }

    static LinearLayout body(MaterialCardView card) {
        return (LinearLayout) card.getChildAt(0);
    }

    /** A card with a heading. */
    MaterialCardView titledCard(String title) {
        MaterialCardView card = card();
        body(card).addView(heading(title));
        return card;
    }

    /** A card heading: sentence case, text colour, medium weight. */
    TextView heading(String s) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextColor(text);
        t.setTextSize(14);
        t.setTypeface(MEDIUM);
        t.setPadding(0, 0, 0, dp(8));
        return t;
    }

    /** A small label over a figure (dashboard tiles, metric sections). */
    TextView label(String s) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextColor(muted);
        t.setTextSize(12);
        t.setPadding(0, 0, 0, dp(4));
        return t;
    }

    TextView title(String s) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextColor(text);
        t.setTextSize(16);
        t.setTypeface(MEDIUM);
        return t;
    }

    TextView text(String s) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextColor(text);
        t.setTextSize(14);
        t.setLineSpacing(0, 1.15f);
        return t;
    }

    TextView hint(String s) {
        TextView t = text(s);
        t.setTextColor(muted);
        t.setTextSize(13);
        return t;
    }

    TextView mono(String s) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTypeface(Typeface.MONOSPACE);
        t.setTextSize(12);
        t.setTextColor(text);
        t.setTextIsSelectable(true);
        t.setLineSpacing(0, 1.1f);
        return t;
    }

    /** The server state: a sentence-case word in its status colour. */
    TextView badge(String s, int color) {
        TextView t = new TextView(c);
        setBadge(t, s, color);
        t.setTextSize(14);
        t.setTypeface(MEDIUM);
        t.setGravity(Gravity.CENTER_VERTICAL);
        return t;
    }

    void setBadge(TextView t, String s, int color) {
        setBadge(t, s, color, false);
    }

    /** {@code live} puts the ember dot before the word: the one mark of a running server, used nowhere else. */
    void setBadge(TextView t, String s, int color, boolean live) {
        t.setText(s);
        t.setTextColor(color);
        if (live) {
            GradientDrawable dot = new GradientDrawable();
            dot.setShape(GradientDrawable.OVAL);
            dot.setColor(ember);
            dot.setSize(dp(8), dp(8));
            t.setCompoundDrawablesRelativeWithIntrinsicBounds(dot, null, null, null);
            t.setCompoundDrawablePadding(dp(8));
        } else {
            t.setCompoundDrawablesRelativeWithIntrinsicBounds(null, null, null, null);
        }
    }

    /** A thin rule between parts of a card. */
    View divider() {
        View v = new View(c);
        v.setBackgroundColor(edge);
        v.setLayoutParams(new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)));
        return v;
    }

    // ------------------------------------------------------------------------------------------------ buttons

    /** The main action of a card: deep ember, light text (4.5:1). */
    MaterialButton primary(String s, int icon) {
        MaterialButton b = new MaterialButton(c);
        b.setText(s);
        b.setAllCaps(false);
        b.setBackgroundTintList(ColorStateList.valueOf(emberDeep));
        b.setTextColor(onEmber);
        b.setCornerRadius(dp(8));
        icon(b, icon, onEmber);
        return b;
    }

    /** A plain action: hairline rim, text colour. */
    MaterialButton secondary(String s, int icon) {
        MaterialButton b = new MaterialButton(c, null, com.google.android.material.R.attr.materialButtonOutlinedStyle);
        b.setText(s);
        b.setAllCaps(false);
        b.setTextColor(text);
        b.setStrokeColor(ColorStateList.valueOf(edgeStrong));
        b.setStrokeWidth(dp(1));
        b.setCornerRadius(dp(8));
        b.setRippleColor(ColorStateList.valueOf(Color.argb(48, Color.red(text), Color.green(text), Color.blue(text))));
        icon(b, icon, text2);
        return b;
    }

    /** A destructive action: dark red fill, red rim. */
    MaterialButton danger(String s, int icon) {
        MaterialButton b = new MaterialButton(c);
        b.setText(s);
        b.setAllCaps(false);
        b.setBackgroundTintList(ColorStateList.valueOf(errorDeep));
        b.setStrokeColor(ColorStateList.valueOf(errorEdge));
        b.setStrokeWidth(dp(1));
        b.setTextColor(onError);
        b.setCornerRadius(dp(8));
        icon(b, icon, onError);
        return b;
    }

    /** A text-only action, for small things (copy, share). */
    MaterialButton flat(String s, int icon) {
        MaterialButton b = new MaterialButton(c, null, com.google.android.material.R.attr.borderlessButtonStyle);
        b.setText(s);
        b.setAllCaps(false);
        b.setTextColor(text2);
        icon(b, icon, text2);
        return b;
    }

    /** Big tiles of the dashboard's actions. */
    MaterialButton big(MaterialButton b) {
        b.setMinHeight(dp(56));
        b.setTextSize(14);
        b.setIconPadding(dp(8));
        b.setInsetTop(dp(4));
        b.setInsetBottom(dp(4));
        return b;
    }

    /** Every icon: 20 dp, tinted with its text role. */
    private void icon(MaterialButton b, int icon, int tint) {
        if (icon != 0) {
            b.setIconResource(icon);
            b.setIconTint(ColorStateList.valueOf(tint));
            b.setIconSize(dp(20));
        }
    }

    // ------------------------------------------------------------------------------------------------ fields

    /** An outlined text field with a label and a helper line under it. */
    TextInputLayout field(String label, String helper, String value, int inputType) {
        TextInputLayout l = new TextInputLayout(c, null,
                com.google.android.material.R.attr.textInputOutlinedStyle);
        l.setHint(label);
        if (helper != null && !helper.isEmpty()) {
            l.setHelperText(helper);
            l.setHelperTextColor(ColorStateList.valueOf(muted));
        }
        l.setBoxStrokeColor(text2);
        l.setHintTextColor(ColorStateList.valueOf(text2));
        l.setDefaultHintTextColor(ColorStateList.valueOf(muted));
        l.setBoxCornerRadii(dp(8), dp(8), dp(8), dp(8));
        TextInputEditText e = new TextInputEditText(l.getContext());
        e.setText(value);
        e.setTextColor(text);
        e.setInputType(inputType == 0 ? InputType.TYPE_CLASS_TEXT : inputType);
        if ((e.getInputType() & InputType.TYPE_TEXT_FLAG_MULTI_LINE) == 0) {
            e.setSingleLine(true);
        }
        l.addView(e, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        return l;
    }

    static String value(TextInputLayout l) {
        return l.getEditText() == null || l.getEditText().getText() == null ? ""
                : l.getEditText().getText().toString().trim();
    }

    static void setValue(TextInputLayout l, String v) {
        if (l.getEditText() != null) {
            l.getEditText().setText(v);
        }
    }
}
