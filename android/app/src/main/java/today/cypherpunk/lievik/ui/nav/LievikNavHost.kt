package today.cypherpunk.lievik.ui.nav

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import today.cypherpunk.lievik.ui.screens.activity.ActivityScreen
import today.cypherpunk.lievik.ui.screens.activity.DevLogsScreen
import today.cypherpunk.lievik.ui.screens.ask.AskScreen
import today.cypherpunk.lievik.ui.screens.billing.BillingScreen
import today.cypherpunk.lievik.ui.screens.channels.AiChannelsScreen
import today.cypherpunk.lievik.ui.screens.channels.ChannelEditScreen
import today.cypherpunk.lievik.ui.screens.channels.ChannelScreen
import today.cypherpunk.lievik.ui.screens.channels.ChannelsScreen
import today.cypherpunk.lievik.ui.screens.content.ContentEditorScreen
import today.cypherpunk.lievik.ui.screens.content.ContentListScreen
import today.cypherpunk.lievik.ui.screens.content.ContentNewScreen
import today.cypherpunk.lievik.ui.screens.dashboard.DashboardScreen
import today.cypherpunk.lievik.ui.screens.events.EventDetailScreen
import today.cypherpunk.lievik.ui.screens.events.EventsScreen
import today.cypherpunk.lievik.ui.screens.events.ManualEventScreen
import today.cypherpunk.lievik.ui.screens.more.MoreScreen
import today.cypherpunk.lievik.ui.screens.settings.ApiTokensScreen
import today.cypherpunk.lievik.ui.screens.settings.SettingsScreen
import today.cypherpunk.lievik.ui.screens.settings.TemplatesScreen
import today.cypherpunk.lievik.ui.screens.sources.SourceEditScreen
import today.cypherpunk.lievik.ui.screens.sources.SourceScreen
import today.cypherpunk.lievik.ui.screens.sources.SourcesScreen

private val idArg = listOf(navArgument("id") { type = NavType.LongType })

@Composable
fun LievikNavHost(nav: NavHostController, modifier: Modifier = Modifier) {
    val back: () -> Unit = { nav.popBackStack() }
    NavHost(nav, startDestination = Routes.DASHBOARD, modifier = modifier) {
        composable(Routes.DASHBOARD) { DashboardScreen(nav) }
        composable(Routes.CHANNELS) { ChannelsScreen(nav) }
        composable(Routes.EVENTS) { EventsScreen(nav) }
        composable(Routes.ASK) { AskScreen(nav) }
        composable(Routes.MORE) { MoreScreen(nav) }

        composable(Routes.SOURCES) { SourcesScreen(nav) }
        composable(Routes.SOURCE_NEW) { SourceEditScreen(null, nav) }
        composable(Routes.SOURCE, idArg) { SourceScreen(it.arguments!!.getLong("id"), nav) }
        composable(Routes.SOURCE_EDIT, idArg) { SourceEditScreen(it.arguments!!.getLong("id"), nav) }

        composable(Routes.CHANNEL_NEW) { ChannelEditScreen(null, nav) }
        composable(Routes.CHANNELS_AI) { AiChannelsScreen(nav) }
        composable(Routes.CHANNEL, idArg + navArgument("selected") { type = NavType.LongType; defaultValue = 0L }) {
            ChannelScreen(it.arguments!!.getLong("id"), nav, selectedEventId = it.arguments!!.getLong("selected").takeIf { id -> id > 0 })
        }
        composable(Routes.CHANNEL_EDIT, idArg) { ChannelEditScreen(it.arguments!!.getLong("id"), nav) }
        composable(Routes.CONTENTS, idArg) { ContentListScreen(it.arguments!!.getLong("id"), nav) }
        composable(
            Routes.CONTENT_NEW,
            idArg + navArgument("ids") { type = NavType.StringType; defaultValue = "" },
        ) {
            val ids = it.arguments?.getString("ids").orEmpty().split(",").mapNotNull(String::toLongOrNull)
            ContentNewScreen(it.arguments!!.getLong("id"), ids, nav)
        }
        composable(
            Routes.CONTENT,
            listOf(
                navArgument("cid") { type = NavType.LongType },
                navArgument("id") { type = NavType.LongType },
                navArgument("generate") { type = NavType.BoolType; defaultValue = false },
            ),
        ) { ContentEditorScreen(it.arguments!!.getLong("cid"), it.arguments!!.getLong("id"), it.arguments!!.getBoolean("generate"), nav) }

        composable(Routes.EVENT, idArg) { EventDetailScreen(it.arguments!!.getLong("id"), nav) }
        composable(Routes.MANUAL_EVENT) { ManualEventScreen(nav) }

        composable(Routes.ACTIVITY) { ActivityScreen(nav) }
        composable(Routes.DEV_LOGS, idArg) { DevLogsScreen(it.arguments!!.getLong("id"), onBack = back) }

        composable(Routes.SETTINGS) { SettingsScreen(nav) }
        composable(Routes.TEMPLATES) { TemplatesScreen(onBack = back) }
        composable(Routes.TOKENS) { ApiTokensScreen(onBack = back) }
        composable(Routes.BILLING) { BillingScreen(onBack = back) }
    }
}
