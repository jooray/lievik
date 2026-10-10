package today.cypherpunk.lievik

import android.app.Application
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.crossfade

class LievikApp : Application(), SingletonImageLoader.Factory {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        if (container.session.signedIn.value) SyncScheduler.schedule(this)
    }

    /** Images (avatars, inline note images) load through a plain client: no API token on third-party hosts. */
    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .components { add(OkHttpNetworkFetcherFactory(callFactory = { okhttp3.OkHttpClient() })) }
            .crossfade(true)
            .build()
}
