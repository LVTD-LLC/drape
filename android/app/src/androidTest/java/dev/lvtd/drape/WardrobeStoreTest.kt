package dev.lvtd.drape

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class WardrobeStoreTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(): ByteArray = InstrumentationRegistry.getInstrumentation().context.assets.open("cardigan-source.png").use { it.readBytes() }
    @Test fun reopenPreservesOriginalGeneratedPhotosEditsAndLookMembership() {
        val database = "test-${UUID.randomUUID()}.db"
        var store = WardrobeStore(context, database)
        try {
            val bytes = Photos.normalize(fixture())
            val original = store.writePhoto(bytes)
            val studio = store.writePhoto(bytes)
            val piece = Piece(photos = listOf(original), studio = studio, fields = mapOf("name" to "My cardigan", "material" to "100% cotton"), favorite = true, analyzed = true)
            store.save(piece)
            val look = Look(name = "Everyday", ids = listOf(piece.id)); store.save(look)
            store.close(); store = WardrobeStore(context, database)
            val restored = store.pieces().single()
            assertEquals(piece, restored)
            assertArrayEquals(bytes, store.photo(restored.photos.single()).readBytes())
            assertArrayEquals(bytes, store.photo(restored.studio!!).readBytes())
            assertEquals(look, store.looks().single())
            store.delete(restored)
            assertTrue(store.pieces().isEmpty())
            assertTrue(store.looks().single().ids.isEmpty())
            assertFalse(store.photo(original).exists())
        } finally { store.close(); context.deleteDatabase(database); store.photoDir.deleteRecursively() }
    }
    @Test fun analysisPreservesUserEditsAndDeliberatelyClearedFields() {
        val piece = Piece(fields = mapOf("name" to "My name", "size" to ""), edited = setOf("size"))
        val result = applyAnalysis(piece, mapOf("name" to "AI name", "size" to "M", "color" to "Cream"))
        assertEquals("My name", result.fields["name"])
        assertEquals("", result.fields["size"])
        assertEquals("Cream", result.fields["color"])
        assertTrue(result.analyzed)
    }
    @Test fun analysisDoesNotAttachEvidenceToManualValuesOrChangeTaxonomy() {
        val piece = Piece(fields = mapOf("price" to "20", "currency" to "EUR", "condition" to "Good", "category" to "Shoes"), edited = setOf("price", "currency", "condition", "category"))
        val result = applyAnalysis(piece, mapOf("price" to "90", "priceSource" to "photo", "priceEvidence" to "Tag", "conditionSource" to "photo", "conditionEvidence" to "No wear", "subcategory" to "Shirts"))
        assertEquals("20", result.fields["price"])
        assertNull(result.fields["priceEvidence"])
        assertNull(result.fields["conditionSource"])
        assertNull(result.fields["subcategory"])
    }
    @Test fun gatewayContentTypeHasNoCharsetParameter() {
        var requests = 0
        val client = WardrobeAI.defaultClient().newBuilder().addInterceptor { chain ->
            requests++
            assertEquals("application/json", chain.request().body!!.contentType().toString())
            throw java.io.IOException("Synthetic offline failure")
        }.build()
        val ai = WardrobeAI(context, client, "https://example.invalid/", "test-only")
        assertTrue(runCatching { ai.analyze(listOf(Photos.normalize(fixture()))) }.isFailure)
        assertEquals("Do not automatically retry paid requests", 1, requests)
    }
    @Test fun rejectsInvalidPhotoPathsAndImages() {
        val database = "test-${UUID.randomUUID()}.db"
        val store = WardrobeStore(context, database)
        try {
            assertTrue(runCatching { store.photo("../wardrobe.db") }.isFailure)
            assertTrue(runCatching { Photos.normalize("not a photo".toByteArray()) }.isFailure)
        } finally { store.close(); context.deleteDatabase(database); store.photoDir.deleteRecursively() }
    }
}
