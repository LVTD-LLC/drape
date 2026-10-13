package dev.lvtd.drape

import android.app.Application
import android.net.Uri
import android.util.Base64
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject

class DrapeApplication : Application() {
    val model by lazy { DrapeModel(this) }
}

/** App-owned work survives activity recreation, never process death: interrupted work is manual. */
class DrapeModel(private val app: Application) {
    val store = WardrobeStore(app)
    val ai = WardrobeAI(app)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutex = Mutex()
    private val processing = mutableSetOf<String>()
    var pieces by mutableStateOf<List<Piece>>(emptyList()); private set
    var looks by mutableStateOf<List<Look>>(emptyList()); private set
    var loaded by mutableStateOf(false); private set
    var busy by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null)
    var notice by mutableStateOf<String?>(null)
    var draft by mutableStateOf<List<ByteArray>>(emptyList()); private set
    val prefs = app.getSharedPreferences("privacy", 0)
    var lockEnabled by mutableStateOf(prefs.getBoolean("lock", false)); private set
    var unlocked by mutableStateOf(!lockEnabled)
    init { run {
        mutex.withLock {
            withContext(Dispatchers.IO) { store.pieces().filter { it.state == "preparing" }.forEach { store.save(it.copy(state = "interrupted")) } }
            refresh()
        }
        loaded = true
    } }
    private fun run(block: suspend () -> Unit) = scope.launch {
        try { block() } catch (e: CancellationException) { throw e }
        catch (_: Exception) { error = "Drape could not complete that action. Your saved wardrobe has been kept. Please try again." }
    }
    private suspend fun refresh() {
        val data = withContext(Dispatchers.IO) { store.pieces() to store.looks() }
        pieces = data.first; looks = data.second
    }
    private suspend fun change(id: String, transform: (Piece) -> Piece) = mutex.withLock {
        val current = pieces.find { it.id == id } ?: return@withLock
        withContext(Dispatchers.IO) { store.save(transform(current)) }
        refresh()
    }
    fun importPhotos(uris: List<Uri>) {
        if(busy) return
        busy = true
        run {
            try {
                val capacity = (6 - draft.size).coerceAtLeast(0)
                val images = withContext(Dispatchers.IO) { uris.take(capacity).map { uri ->
                    app.contentResolver.openInputStream(uri).use { stream -> Photos.normalize(requireNotNull(stream).readBytesLimited(Photos.MAX_INPUT)) }
                } }
                draft = draft + images
            } finally { busy = false }
        }
    }
    fun removeDraft(index: Int) { draft = draft.filterIndexed { i, _ -> i != index } }
    fun discardDraft() { if(!busy) draft = emptyList() }
    fun add(prepare: Boolean, done: (String) -> Unit) {
        if(busy || draft.isEmpty() || !loaded) return
        busy = true
        val source = draft.toList()
        run {
            try {
                val piece = mutex.withLock {
                    val saved = withContext(Dispatchers.IO) {
                        val refs = source.map { store.writePhoto(it) }
                        Piece(photos = refs).also { store.save(it) }
                    }
                    refresh(); saved
                }
                draft = emptyList(); done(piece.id)
                if(prepare) prepare(piece.id)
            } finally { busy = false }
        }
    }
    fun prepare(id: String) {
        val piece = pieces.find { it.id == id } ?: return
        if(piece.complete || !processing.add(id)) return
        run {
            try {
                change(id) { it.copy(state = "preparing") }
                if(!piece.analyzed) {
                    val fields = withContext(Dispatchers.IO) { ai.analyze(piece.photos.map { store.photo(it).readBytes() }) }
                    change(id) { applyAnalysis(it, fields) }
                }
                val current = pieces.find { it.id == id } ?: return@run
                if(current.studio == null) {
                    val bytes = withContext(Dispatchers.IO) { ai.studio(store.photo(current.photos.first()).readBytes()) }
                    mutex.withLock {
                        val latest = pieces.find { it.id == id } ?: return@withLock
                        withContext(Dispatchers.IO) {
                            val ref = store.writePhoto(bytes)
                            store.save(latest.copy(studio = ref, useStudio = "cover" !in latest.edited, state = "ready"))
                        }
                        refresh()
                    }
                } else change(id) { it.copy(state = "ready") }
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) {
                change(id) { it.copy(state = "unfinished") }
                error = "Preparation could not finish. Your photos and completed steps are saved. Use Finish preparing when you’re ready; Drape won’t retry automatically."
            } finally { processing.remove(id) }
        }
    }
    fun favorite(id: String) { run { change(id) { it.copy(favorite = !it.favorite) } } }
    fun cover(id: String, studio: Boolean) { run { change(id) { it.copy(useStudio = studio, edited = it.edited + "cover") } } }
    fun edit(id: String, baseline: Map<String, String>, fields: Map<String, String>, done: () -> Unit) {
        val delta = fields.filter { (k, v) -> v != baseline[k].orEmpty() }.toMutableMap()
        if(delta.containsKey("price") || delta.containsKey("currency")) {
            val amount = fields["price"].orEmpty(); val currency = fields["currency"].orEmpty().uppercase()
            if(amount.isNotBlank()) {
                if(!amount.matches(Regex("(0|[1-9][0-9]{0,11})(\\.[0-9]{1,4})?")) || runCatching { java.util.Currency.getInstance(currency) }.isFailure) {
                    error = "Enter a non-negative price and a valid currency such as EUR or USD."; return
                }
            }
            delta["price"] = amount; delta["currency"] = if(amount.isBlank()) "" else currency
            delta["priceSource"] = "user"; delta["priceEvidence"] = ""
        }
        if(delta.containsKey("condition")) { delta["conditionSource"] = "user"; delta["conditionEvidence"] = "" }
        if(delta.containsKey("tags")) delta["tags"] = delta.getValue("tags").split(',').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.distinct().joinToString(", ")
        run { change(id) { it.copy(fields = it.fields + delta, edited = it.edited + delta.keys) }; done() }
    }
    fun delete(id: String, done: () -> Unit) { run { mutex.withLock {
        val piece = pieces.find { it.id == id } ?: return@withLock
        withContext(Dispatchers.IO) { store.delete(piece) }; refresh()
    }; done() } }
    fun saveLook(name: String, ids: List<String>, done: () -> Unit) { run { mutex.withLock {
        withContext(Dispatchers.IO) { store.save(Look(name = name.trim(), ids = ids.filter { id -> pieces.any { it.id == id } })) }; refresh()
    }; done() } }
    fun deleteLook(id: String) { run { mutex.withLock { withContext(Dispatchers.IO) { store.deleteLook(id) }; refresh() } } }
    fun setLock(enabled: Boolean) { prefs.edit().putBoolean("lock", enabled).apply(); lockEnabled = enabled }

    fun export(uri: Uri) { run {
        busy = true
        try {
            mutex.withLock { withContext(Dispatchers.IO) {
                val all = store.pieces()
                val refs = all.flatMap { it.photos + listOfNotNull(it.studio) }.distinct()
                require(refs.sumOf { store.photo(it).length() } < 65_000_000) { "Backup is too large" }
                val photos = JSONObject(); refs.forEach { photos.put(it, Base64.encodeToString(store.photo(it).readBytes(), Base64.NO_WRAP)) }
                val data = JSONObject().put("format", "drape-android").put("version", 1)
                    .put("pieces", JSONArray(all.map { it.json() })).put("looks", JSONArray(store.looks().map { it.json() })).put("photos", photos).toString().toByteArray()
                require(data.size <= 100_000_000)
                app.contentResolver.openOutputStream(uri, "wt").use { requireNotNull(it).write(data) }
            } }
            notice = "Wardrobe backup saved. Keep it somewhere safe."
        } finally { busy = false }
    } }
    fun restore(uri: Uri) { run {
        busy = true
        try {
            mutex.withLock { withContext(Dispatchers.IO) {
                val data = app.contentResolver.openInputStream(uri).use { requireNotNull(it).readBytesLimited(100_000_000) }
                val json = JSONObject(String(data, Charsets.UTF_8))
                require(json.getString("format") == "drape-android" && json.getInt("version") == 1)
                val records = json.getJSONArray("pieces").let { a -> (0 until a.length()).map { Piece.parse(a.getJSONObject(it)) } }
                val outfits = json.getJSONArray("looks").let { a -> (0 until a.length()).map { Look.parse(a.getJSONObject(it)) } }
                require(records.map { it.id }.distinct().size == records.size)
                val photoJson = json.getJSONObject("photos")
                val photoData = photoJson.keys().asSequence().associateWith { key ->
                    store.photo(key) // validate the reference without accessing it
                    Base64.decode(photoJson.getString(key), Base64.DEFAULT).also { bytes ->
                        require(bytes.size <= Photos.MAX_INPUT)
                        val opts = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
                        require(opts.outWidth in 1..3600 && opts.outHeight in 1..3600)
                    }
                }
                records.forEach { p ->
                    java.util.UUID.fromString(p.id)
                    require(p.photos.size in 1..6)
                    require((p.photos + listOfNotNull(p.studio)).all { it in photoData })
                }
                val existing = store.pieces().map { it.id }.toSet()
                val allIds = existing + records.map { it.id }
                outfits.forEach { java.util.UUID.fromString(it.id); require(it.ids.all { id -> id in allIds }) }
                val written = mutableListOf<String>()
                val db = store.writableDatabase
                db.beginTransaction()
                try {
                    records.filter { it.id !in existing }.forEach { p ->
                        val mappings = (p.photos + listOfNotNull(p.studio)).associateWith { old -> store.writePhoto(photoData.getValue(old)).also { written.add(it) } }
                        store.save(p.copy(photos = p.photos.map { mappings.getValue(it) }, studio = p.studio?.let { mappings.getValue(it) }, state = if(p.state == "preparing") "interrupted" else p.state))
                    }
                    val existingLooks = store.looks().map { it.id }.toSet()
                    outfits.filter { it.id !in existingLooks }.forEach { store.save(it) }
                    db.setTransactionSuccessful()
                } catch(e: Exception) { written.forEach { store.photo(it).delete() }; throw e }
                finally { db.endTransaction() }
            }; refresh() }
            notice = "Backup restored. Existing pieces were kept."
        } finally { busy = false }
    } }
}
