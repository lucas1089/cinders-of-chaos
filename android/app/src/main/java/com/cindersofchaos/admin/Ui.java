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

/** The view builders of every screen: the game's palette, cards, buttons and fields, all made in code. */
final class Ui {
    final Context c;
    final int iron0;
    final int iron1;
    final int iron2;
    final int iron3;
    final int iron4;
    final int text;
    final int bright;
    final int muted;
    final int gold;
    final int goldLight;
    final int goldDark;
    final int blood;
    final int bloodDark;
    final int ember;
    final int ok;

    Ui(Context c) {
        this.c = c;
        iron0 = col(R.color.iron0);
        iron1 = col(R.color.iron1);
        iron2 = col(R.color.iron2);
        iron3 = col(R.color.iron3);
        iron4 = col(R.color.iron4);
        text = col(R.color.text);
        bright = col(R.color.text_bright);
        muted = col(R.color.muted);
        gold = col(R.color.gold);
        goldLight = col(R.color.gold_light);
        goldDark = col(R.color.gold_dark);
        blood = col(R.color.blood);
        bloodDark = col(R.color.blood_dark);
        ember = col(R.color.ember);
        ok = col(R.color.ok);
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
        l.setPadding(dp(14), dp(10), dp(14), dp(24));
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

    /** A dark card with a thin iron rim; returns the card, its content is {@link #body(MaterialCardView)}. */
    MaterialCardView card() {
        MaterialCardView card = new MaterialCardView(c);
        card.setCardBackgroundColor(iron2);
        card.setStrokeColor(iron4);
        card.setStrokeWidth(dp(1));
        card.setRadius(dp(14));
        card.setCardElevation(0);
        LinearLayout body = column();
        body.setPadding(dp(16), dp(14), dp(16), dp(16));
        card.addView(body, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        return card;
    }

    static LinearLayout body(MaterialCardView card) {
        return (LinearLayout) card.getChildAt(0);
    }

    /** A card with a gold small-caps heading. */
    MaterialCardView titledCard(String title) {
        MaterialCardView card = card();
        body(card).addView(heading(title));
        return card;
    }

    TextView heading(String s) {
        TextView t = new TextView(c);
        t.setText(s.toUpperCase(java.util.Locale.ROOT));
        t.setTextColor(gold);
        t.setTextSize(12);
        t.setLetterSpacing(0.12f);
        t.setTypeface(Typeface.create(Typeface.SERIF, Typeface.BOLD));
        t.setPadding(0, 0, 0, dp(8));
        return t;
    }

    TextView title(String s) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextColor(bright);
        t.setTextSize(17);
        t.setTypeface(Typeface.create(Typeface.SERIF, Typeface.BOLD));
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

    /** A pill with a coloured dot: the server state. */
    TextView badge(String s, int color) {
        TextView t = new TextView(c);
        setBadge(t, s, color);
        t.setTextSize(12);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setLetterSpacing(0.06f);
        t.setPadding(dp(10), dp(4), dp(12), dp(4));
        t.setGravity(Gravity.CENTER_VERTICAL);
        return t;
    }

    void setBadge(TextView t, String s, int color) {
        t.setText("●  " + s);
        t.setTextColor(color);
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(dp(14));
        bg.setColor(Color.argb(40, Color.red(color), Color.green(color), Color.blue(color)));
        bg.setStroke(dp(1), Color.argb(140, Color.red(color), Color.green(color), Color.blue(color)));
        t.setBackground(bg);
    }

    /** A thin rule between parts of a card. */
    View divider() {
        View v = new View(c);
        v.setBackgroundColor(iron4);
        v.setLayoutParams(new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)));
        return v;
    }

    // ------------------------------------------------------------------------------------------------ buttons

    /** The main action: gold, dark text. */
    MaterialButton primary(String s, int icon) {
        MaterialButton b = new MaterialButton(c);
        b.setText(s);
        b.setAllCaps(false);
        b.setBackgroundTintList(ColorStateList.valueOf(gold));
        b.setTextColor(iron0);
        b.setCornerRadius(dp(12));
        icon(b, icon, iron0);
        return b;
    }

    /** A plain action: iron, parchment text, gold rim. */
    MaterialButton secondary(String s, int icon) {
        MaterialButton b = new MaterialButton(c, null, com.google.android.material.R.attr.materialButtonOutlinedStyle);
        b.setText(s);
        b.setAllCaps(false);
        b.setTextColor(text);
        b.setStrokeColor(ColorStateList.valueOf(goldDark));
        b.setStrokeWidth(dp(1));
        b.setCornerRadius(dp(12));
        b.setRippleColor(ColorStateList.valueOf(Color.argb(60, Color.red(gold), Color.green(gold), Color.blue(gold))));
        icon(b, icon, gold);
        return b;
    }

    /** A destructive action: crimson. */
    MaterialButton danger(String s, int icon) {
        MaterialButton b = new MaterialButton(c);
        b.setText(s);
        b.setAllCaps(false);
        b.setBackgroundTintList(ColorStateList.valueOf(blood));
        b.setTextColor(bright);
        b.setCornerRadius(dp(12));
        icon(b, icon, bright);
        return b;
    }

    /** A text-only action, for small things (copy, share). */
    MaterialButton flat(String s, int icon) {
        MaterialButton b = new MaterialButton(c, null, com.google.android.material.R.attr.borderlessButtonStyle);
        b.setText(s);
        b.setAllCaps(false);
        b.setTextColor(goldLight);
        icon(b, icon, goldLight);
        return b;
    }

    /** Big tiles of the dashboard's actions. */
    MaterialButton big(MaterialButton b) {
        b.setMinHeight(dp(60));
        b.setTextSize(15);
        b.setIconSize(dp(22));
        b.setIconPadding(dp(10));
        b.setInsetTop(dp(4));
        b.setInsetBottom(dp(4));
        return b;
    }

    private void icon(MaterialButton b, int icon, int tint) {
        if (icon != 0) {
            b.setIconResource(icon);
            b.setIconTint(ColorStateList.valueOf(tint));
            b.setIconSize(dp(18));
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
        l.setBoxStrokeColor(gold);
        l.setHintTextColor(ColorStateList.valueOf(gold));
        l.setDefaultHintTextColor(ColorStateList.valueOf(muted));
        l.setBoxCornerRadii(dp(10), dp(10), dp(10), dp(10));
        TextInputEditText e = new TextInputEditText(l.getContext());
        e.setText(value);
        e.setTextColor(bright);
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
