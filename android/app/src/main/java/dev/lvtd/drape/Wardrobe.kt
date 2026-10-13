package dev.lvtd.drape

import android.content.Context
import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID

val categories = listOf("Tops", "Bottoms", "Dresses", "Outerwear", "Shoes", "Bags", "Accessories", "Other")
val detailFields = listOf("name", "category", "subcategory", "color", "brand", "size", "material", "pattern", "season", "care", "notes")
val attributeFields = listOf("typeDetail", "tags", "price", "currency", "priceEvidence", "priceSource", "condition", "conditionEvidence", "conditionSource")
val editableFields = detailFields + listOf("typeDetail", "tags", "price", "currency", "condition")
val taxonomy = mapOf(
    "Tops" to listOf("T-shirts", "Shirts", "Blouses", "Tank tops", "Sweaters", "Cardigans", "Hoodies", "Sweatshirts"),
    "Bottoms" to listOf("Jeans", "Trousers", "Shorts", "Skirts", "Leggings"),
    "Dresses" to listOf("Dresses", "Jumpsuits", "Playsuits"),
    "Outerwear" to listOf("Coats", "Jackets", "Blazers", "Vests", "Raincoats"),
    "Shoes" to listOf("Sneakers", "Boots", "Sandals", "Heels", "Flats", "Loafers", "Slippers"),
    "Bags" to listOf("Handbags", "Shoulder bags", "Crossbody bags", "Totes", "Backpacks", "Clutches", "Wallets"),
    "Accessories" to listOf("Hats", "Rings", "Necklaces", "Watches", "Bracelets", "Earrings", "Brooches", "Scarves", "Belts", "Gloves", "Sunglasses", "Ties", "Hair accessories"),
    "Other" to listOf("Underwear", "Socks", "Swimwear", "Sleepwear", "Other")
)

data class Piece(
    val id: String = UUID.randomUUID().toString(),
    val created: Long = System.currentTimeMillis(),
    val fields: Map<String, String> = emptyMap(),
    val photos: List<String> = emptyList(),
    val studio: String? = null,
    val useStudio: Boolean = false,
    val favorite: Boolean = false,
    val analyzed: Boolean = false,
    val state: String = "saved",
    val edited: Set<String> = emptySet()
) {
    val name get() = fields["name"].orEmpty().ifBlank { "New piece" }
    val category get() = fields["category"].orEmpty().ifBlank { "Other" }
    val cover get() = if (useStudio) studio ?: photos.first() else photos.first()
    val complete get() = analyzed && studio != null
    fun json() = JSONObject().put("id", id).put("created", created).put("fields", JSONObject(fields))
        .put("photos", JSONArray(photos)).put("studio", studio).put("useStudio", useStudio)
        .put("favorite", favorite).put("analyzed", analyzed).put("state", state).put("edited", JSONArray(edited.toList()))
    companion object {
        fun parse(j: JSONObject): Piece {
            val f = j.getJSONObject("fields")
            return Piece(j.getString("id"), j.getLong("created"), f.keys().asSequence().associateWith { f.getString(it) },
                j.getJSONArray("photos").strings(), j.optString("studio").takeIf { it.isNotEmpty() && it != "null" },
                j.optBoolean("useStudio"), j.optBoolean("favorite"), j.optBoolean("analyzed"), j.optString("state", "saved"),
                j.optJSONArray("edited")?.strings()?.toSet() ?: emptySet())
        }
    }
}
data class Look(val id: String = UUID.randomUUID().toString(), val name: String, val ids: List<String>) {
    fun json() = JSONObject().put("id", id).put("name", name).put("ids", JSONArray(ids))
    companion object { fun parse(j: JSONObject) = Look(j.getString("id"), j.getString("name"), j.getJSONArray("ids").strings()) }
}
fun JSONArray.strings() = (0 until length()).map { getString(it) }

/** Schema 1 is the first Android layout. Future changes must retain and migrate it. */
class WardrobeStore(context: Context, name: String = "wardrobe.db") : SQLiteOpenHelper(context, name, null, 1) {
    val photoDir = File(context.filesDir, "$name-photos").apply { mkdirs() }
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE pieces (id TEXT PRIMARY KEY NOT NULL, json TEXT NOT NULL)")
        db.execSQL("CREATE TABLE looks (id TEXT PRIMARY KEY NOT NULL, json TEXT NOT NULL)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) { error("A wardrobe migration is required") }
    fun pieces(): List<Piece> = readableDatabase.rawQuery("SELECT json FROM pieces", null).use { c -> buildList { while(c.moveToNext()) add(Piece.parse(JSONObject(c.getString(0)))) } }.sortedByDescending { it.created }
    fun looks(): List<Look> = readableDatabase.rawQuery("SELECT json FROM looks", null).use { c -> buildList { while(c.moveToNext()) add(Look.parse(JSONObject(c.getString(0)))) } }
    fun save(piece: Piece) { put("pieces", piece.id, piece.json()) }
    fun save(look: Look) { put("looks", look.id, look.json()) }
    private fun put(table: String, id: String, json: JSONObject) {
        writableDatabase.insertWithOnConflict(table, null, ContentValues().apply { put("id", id); put("json", json.toString()) }, SQLiteDatabase.CONFLICT_REPLACE).also { check(it != -1L) }
    }
    fun photo(name: String): File {
        require(name.matches(Regex("[a-f0-9-]{36}\\.jpg"))) { "Invalid photo reference" }
        return File(photoDir, name)
    }
    fun writePhoto(bytes: ByteArray): String {
        val name = "${UUID.randomUUID()}.jpg"
        val destination = photo(name)
        val temp = File(photoDir, "$name.tmp")
        temp.outputStream().use { it.write(bytes); it.fd.sync() }
        check(temp.renameTo(destination))
        return name
    }
    fun delete(piece: Piece) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete("pieces", "id = ?", arrayOf(piece.id))
            looks().filter { piece.id in it.ids }.forEach { save(it.copy(ids = it.ids - piece.id)) }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        (piece.photos + listOfNotNull(piece.studio)).forEach { photo(it).delete() }
    }
    fun deleteLook(id: String) { writableDatabase.delete("looks", "id = ?", arrayOf(id)) }
}

object Photos {
    const val MAX_INPUT = 30 * 1024 * 1024
    fun normalize(bytes: ByteArray): ByteArray {
        require(bytes.size <= MAX_INPUT) { "Choose a photo smaller than 30 MB." }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "This photo could not be opened." }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 3600) sample *= 2
        val decoded = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }))
        val orientation = ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)
        val matrix = Matrix().apply {
            when(orientation) {
                2 -> setScale(-1f, 1f); 3 -> setRotate(180f); 4 -> setScale(1f, -1f)
                5 -> { setRotate(90f); postScale(-1f, 1f) }; 6 -> setRotate(90f)
                7 -> { setRotate(270f); postScale(-1f, 1f) }; 8 -> setRotate(270f)
            }
        }
        val oriented = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        val scale = minOf(1f, 1800f / maxOf(oriented.width, oriented.height))
        val resized = Bitmap.createScaledBitmap(oriented, (oriented.width * scale).toInt().coerceAtLeast(1), (oriented.height * scale).toInt().coerceAtLeast(1), true)
        val output = ByteArrayOutputStream().also { resized.compress(Bitmap.CompressFormat.JPEG, 90, it) }.toByteArray()
        if(resized !== oriented) resized.recycle()
        if(oriented !== decoded) oriented.recycle()
        decoded.recycle()
        return output
    }
}

/** Merge only empty, unedited fields; edits (including deliberate clearing) win. */
fun applyAnalysis(piece: Piece, generated: Map<String, String>): Piece {
    val allowed = generated.filter { (key, _) -> piece.fields[key].isNullOrBlank() && key !in piece.edited }.toMutableMap()
    // Evidence and its value are one unit; never attach AI evidence to a manual value.
    for (group in listOf(listOf("price", "currency", "priceSource", "priceEvidence"), listOf("condition", "conditionSource", "conditionEvidence"))) {
        if (group.any { it in piece.edited || !piece.fields[it].isNullOrBlank() }) group.forEach { allowed.remove(it) }
    }
    if ("category" in piece.edited) listOf("subcategory", "typeDetail").forEach { allowed.remove(it) }
    return piece.copy(fields = piece.fields + allowed, analyzed = true)
}
