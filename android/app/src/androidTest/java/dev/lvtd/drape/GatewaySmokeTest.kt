package dev.lvtd.drape

import android.net.Uri
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import java.io.File

class GatewaySmokeTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    /** Explicit opt-in: use Add to wardrobe once with a synthetic photo. Never retry. */
    @Test fun syntheticPhotoThroughLiveGateway() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("paidSmoke") == "true")
        val model = (compose.activity.application as DrapeApplication).model
        compose.waitUntil(10_000) { model.loaded }
        val file = File(compose.activity.cacheDir, "synthetic-cardigan.png")
        InstrumentationRegistry.getInstrumentation().context.assets.open("cardigan-source.png").use { source -> file.outputStream().use { source.copyTo(it) } }
        compose.onNodeWithContentDescription("Add a piece").performClick()
        compose.runOnIdle { model.importPhotos(listOf(Uri.fromFile(file))) }
        compose.waitUntil(10_000) { model.draft.isNotEmpty() && !model.busy }
        val original = model.draft.single()
        val previous = model.pieces.map { it.id }.toSet()
        compose.onNodeWithText("Add to wardrobe", substring = false).performScrollTo().performClick()
        compose.waitUntil(10_000) { model.pieces.any { it.id !in previous } }
        val id = model.pieces.first { it.id !in previous }.id
        compose.waitUntil(240_000) { model.pieces.first { it.id == id }.let { it.complete || it.state == "unfinished" } }
        val piece = model.pieces.first { it.id == id }
        assertTrue("Live AI preparation did not complete", piece.complete)
        assertTrue(piece.fields.getValue("name").isNotBlank())
        assertTrue(piece.category in categories)
        assertTrue(piece.useStudio)
        assertArrayEquals(original, model.store.photo(piece.photos.first()).readBytes())
        assertTrue(model.store.photo(piece.studio!!).length() > 1000)
        compose.runOnIdle { model.prepare(id) }
        compose.runOnIdle { assertEquals(piece, model.pieces.first { it.id == id }) }
        file.delete()
        // Leave the synthetic piece on the dedicated emulator for visual inspection.
    }
}
