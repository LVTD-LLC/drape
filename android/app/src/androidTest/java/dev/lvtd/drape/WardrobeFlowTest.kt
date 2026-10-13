package dev.lvtd.drape

import android.net.Uri
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.*
import java.io.File

/** Uses only the synthetic repository fixture. No real wardrobe photos or network requests. */
class WardrobeFlowTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    @Test fun addOfflineEditFavoriteAndDelete() {
        val app = compose.activity.application as DrapeApplication
        val model = app.model
        compose.waitUntil(10_000) { model.loaded }
        val fixture = File(compose.activity.cacheDir, "test-source.png")
        InstrumentationRegistry.getInstrumentation().context.assets.open("cardigan-source.png").use { source -> fixture.outputStream().use { source.copyTo(it) } }
        var addedId: String? = null
        try {
            compose.onNodeWithContentDescription("Add a piece").performClick()
            compose.runOnIdle { model.importPhotos(listOf(Uri.fromFile(fixture))) }
            compose.waitUntil(10_000) { model.draft.isNotEmpty() && !model.busy }
            val before = model.pieces.map { it.id }.toSet()
            compose.onNodeWithText("Save photos only", useUnmergedTree = true).performScrollTo().performClick()
            compose.waitUntil(10_000) { model.pieces.any { it.id !in before } }
            addedId = model.pieces.first { it.id !in before }.id
            assertFalse(model.pieces.first { it.id == addedId }.analyzed)
            compose.onNodeWithText("Edit details").performScrollTo().performClick()
            compose.onNodeWithText("Name").performTextReplacement("Emulator test cardigan")
            compose.onNodeWithText("Save details").performClick()
            compose.waitUntil(5_000) { model.pieces.first { it.id == addedId }.name == "Emulator test cardigan" }
            compose.onNodeWithContentDescription("Add favorite").performScrollTo().performClick()
            compose.waitUntil(5_000) { model.pieces.first { it.id == addedId }.favorite }
            val saved = model.pieces.first { it.id == addedId }
            val original = model.store.photo(saved.photos.first()).readBytes()
            val backup = File(compose.activity.cacheDir, "test-backup.json")
            compose.runOnIdle { model.export(Uri.fromFile(backup)) }
            compose.waitUntil(10_000) { !model.busy && backup.exists() && model.notice != null }
            compose.runOnIdle { model.notice = null }
            compose.onNodeWithText("Delete piece").performScrollTo().performClick()
            compose.onNodeWithText("Delete", substring = false).performClick()
            compose.waitUntil(5_000) { model.pieces.none { it.id == addedId } }
            compose.runOnIdle { model.restore(Uri.fromFile(backup)) }
            compose.waitUntil(10_000) { !model.busy && model.pieces.any { it.id == addedId } }
            val restored = model.pieces.first { it.id == addedId }
            assertEquals(saved.fields, restored.fields)
            assertTrue(restored.favorite)
            assertArrayEquals(original, model.store.photo(restored.photos.first()).readBytes())
            compose.runOnIdle { model.notice = null; model.restore(Uri.fromFile(backup)) }
            compose.waitUntil(10_000) { !model.busy && model.notice != null }
            assertEquals(1, model.pieces.count { it.id == addedId })
            compose.runOnIdle { model.notice = null }
            backup.delete()
        } finally {
            addedId?.let { id -> compose.runOnIdle { model.delete(id) {} }; compose.waitUntil(5_000) { model.pieces.none { it.id == id } } }
            fixture.delete()
        }
    }
}
