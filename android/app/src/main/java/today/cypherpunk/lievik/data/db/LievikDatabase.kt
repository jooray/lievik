package today.cypherpunk.lievik.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [SourceEntity::class, ChannelEntity::class, EventEntity::class, ChannelEventEntity::class, ContentEntity::class],
    version = 2,
    exportSchema = true,
)
abstract class LievikDatabase : RoomDatabase() {
    abstract fun dao(): LievikDao

    companion object {
        /**
         * The database is only a cache of the server, but write a migration for
         * every schema change anyway: the sync `since` lives in the prefs, so a
         * destructively rebuilt cache would only be refilled with what changed
         * after it. The fallback is for downgrades.
         */
        fun create(context: Context): LievikDatabase =
            Room.databaseBuilder(context, LievikDatabase::class.java, "lievik.db")
                .addMigrations(MIGRATION_1_2)
                .fallbackToDestructiveMigration(dropAllTables = true)
                .build()
    }
}

/** Events gained the NIP-21 link; old rows get it when they next change or are opened. */
private val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE events ADD COLUMN nostrUri TEXT")
    }
}
