package today.cypherpunk.lievik

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.CompositionLocalProvider
import today.cypherpunk.lievik.ui.DeepLinks
import today.cypherpunk.lievik.ui.LievikRoot
import today.cypherpunk.lievik.ui.components.LocalContainer
import today.cypherpunk.lievik.ui.theme.LievikTheme

/**
 * The single activity. AppCompat (not plain ComponentActivity) so the per-app
 * language from Settings applies on Android versions before 13 too.
 */
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        handle(intent)
        val container = (application as LievikApp).container
        setContent {
            LievikTheme {
                CompositionLocalProvider(LocalContainer provides container) {
                    LievikRoot()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme == "lievik") DeepLinks.pending.value = data.toString()
    }
}
