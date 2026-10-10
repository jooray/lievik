package today.cypherpunk.lievik.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

/** The web's Tailwind purple, as the brand fallback when dynamic colour is unavailable. */
object Brand {
    val purple50 = Color(0xFFFAF5FF)
    val purple100 = Color(0xFFF3E8FF)
    val purple200 = Color(0xFFE9D5FF)
    val purple300 = Color(0xFFD8B4FE)
    val purple400 = Color(0xFFC084FC)
    val purple600 = Color(0xFF9333EA)
    val purple700 = Color(0xFF7E22CE)
    val purple800 = Color(0xFF6B21A8)
    val purple900 = Color(0xFF581C87)
    val gray50 = Color(0xFFF9FAFB)
    val gray100 = Color(0xFFF3F4F6)
    val gray700 = Color(0xFF374151)
    val gray800 = Color(0xFF1F2937)
    val gray900 = Color(0xFF111827)
    val green600 = Color(0xFF16A34A)
    val amber500 = Color(0xFFF59E0B)
    val red600 = Color(0xFFDC2626)
}

private val Light = lightColorScheme(
    primary = Brand.purple600,
    onPrimary = Color.White,
    primaryContainer = Brand.purple100,
    onPrimaryContainer = Brand.purple900,
    secondary = Brand.purple700,
    secondaryContainer = Brand.purple50,
    onSecondaryContainer = Brand.purple900,
    background = Brand.gray50,
    surface = Color.White,
    surfaceVariant = Brand.gray100,
    error = Brand.red600,
)

private val Dark = darkColorScheme(
    primary = Brand.purple400,
    onPrimary = Brand.purple900,
    primaryContainer = Brand.purple800,
    onPrimaryContainer = Brand.purple100,
    secondary = Brand.purple300,
    secondaryContainer = Brand.purple900,
    onSecondaryContainer = Brand.purple100,
    background = Brand.gray900,
    surface = Brand.gray800,
    surfaceVariant = Brand.gray700,
)

@Composable
fun LievikTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val context = LocalContext.current
    val scheme: ColorScheme = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> Dark
        else -> Light
    }
    MaterialTheme(colorScheme = scheme, content = content)
}

/** Relevance chip colours: the web's purple chip, stronger for high scores. */
@Composable
fun relevanceColors(score: Int): Pair<Color, Color> {
    val scheme = MaterialTheme.colorScheme
    return when {
        score >= 75 -> scheme.primary to scheme.onPrimary
        score >= 50 -> scheme.primaryContainer to scheme.onPrimaryContainer
        else -> scheme.surfaceVariant to scheme.onSurfaceVariant
    }
}
