package dev.lvtd.drape

import android.app.KeyguardManager
import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.mapSaver
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import coil.compose.AsyncImage
import java.io.File

class MainActivity : ComponentActivity() {
    private val model get() = (application as DrapeApplication).model
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val dark = isSystemInDarkTheme()
            val colors = if(dark) darkColorScheme(primary = Color(0xFFD6A1B7), background = Color(0xFF1A1718), surface = Color(0xFF1A1718))
                else lightColorScheme(primary = Color(0xFF593345), background = Color(0xFFF7F5F0), surface = Color(0xFFF7F5F0), secondaryContainer = Color(0xFFEBDDDF))
            MaterialTheme(colorScheme = colors) { DrapeApp(model) }
        }
    }
    override fun onStop() { super.onStop(); if(model.lockEnabled) model.unlocked = false }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DrapeApp(model: DrapeModel) {
    val context = androidx.compose.ui.platform.LocalContext.current
    DisposableEffect(model.lockEnabled) {
        val window = (context as? android.app.Activity)?.window
        if (model.lockEnabled) window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
        else window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
        onDispose { }
    }
    var page by rememberSaveable { mutableStateOf("wardrobe") }
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    val auth = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if(result.resultCode == android.app.Activity.RESULT_OK) model.unlocked = true
    }
    if(model.lockEnabled && !model.unlocked) {
        Surface(Modifier.fillMaxSize()) { Column(Modifier.safeDrawingPadding().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Outlined.Lock, null, Modifier.size(48.dp))
            Text("Your wardrobe is private", fontFamily = FontFamily.Serif, fontSize = 28.sp, modifier = Modifier.padding(vertical = 24.dp))
            Button(onClick = {
                val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                keyguard.createConfirmDeviceCredentialIntent("Unlock Drape", "Confirm your device lock to open your wardrobe")?.let { auth.launch(it) }
            }) { Text("Unlock Drape") }
        } }
        return
    }
    val back = { selected = null; page = "wardrobe" }
    BackHandler(enabled = selected != null || page !in listOf("wardrobe", "looks", "settings")) { back() }
    Scaffold(
        topBar = { TopAppBar(title = { Text(if(selected != null) "Your piece" else when(page) { "add" -> "Add a piece"; "looks" -> "Looks"; "settings" -> "Settings"; else -> "Drape" }, fontFamily = FontFamily.Serif, fontSize = 30.sp) },
            navigationIcon = { if(selected != null || page == "add") IconButton(onClick = back) { Icon(Icons.Outlined.ArrowBack, "Back") } },
            actions = { if(page == "wardrobe" && selected == null) IconButton(onClick = { page = "add" }) { Icon(Icons.Outlined.Add, "Add a piece") } }) },
        bottomBar = { if(selected == null && page != "add") NavigationBar {
            listOf(Triple("wardrobe", "Wardrobe", Icons.Outlined.Checkroom), Triple("looks", "Looks", Icons.Outlined.Style), Triple("settings", "Settings", Icons.Outlined.Settings)).forEach { (id, label, icon) ->
                NavigationBarItem(selected = page == id, onClick = { page = id }, icon = { Icon(icon, label) }, label = { Text(label) })
            }
        } }
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            if(!model.loaded) { CircularProgressIndicator(Modifier.align(Alignment.Center)) }
            else if(selected != null) {
                val piece = model.pieces.find { it.id == selected }
                if(piece != null) DetailScreen(model, piece, back) else Text("This piece is no longer in your wardrobe.", Modifier.padding(24.dp))
            } else when(page) {
                "add" -> AddScreen(model) { selected = it; page = "wardrobe" }
                "looks" -> LooksScreen(model) { selected = it }
                "settings" -> SettingsScreen(model)
                else -> WardrobeScreen(model, { page = "add" }) { selected = it }
            }
        }
    }
    model.error?.let { message -> AlertDialog(onDismissRequest = { model.error = null }, title = { Text("Something needs attention") }, text = { Text(message) }, confirmButton = { TextButton(onClick = { model.error = null }) { Text("OK") } }) }
    model.notice?.let { message -> AlertDialog(onDismissRequest = { model.notice = null }, title = { Text("Drape") }, text = { Text(message) }, confirmButton = { TextButton(onClick = { model.notice = null }) { Text("Done") } }) }
}

@Composable
fun PieceImage(model: DrapeModel, reference: String, description: String, modifier: Modifier = Modifier) {
    AsyncImage(model = model.store.photo(reference), contentDescription = description, contentScale = ContentScale.Fit,
        modifier = modifier.background(Color.White, RoundedCornerShape(18.dp)))
}

@Composable
fun WardrobeScreen(model: DrapeModel, add: () -> Unit, open: (String) -> Unit) {
    var search by rememberSaveable { mutableStateOf("") }
    var category by rememberSaveable { mutableStateOf("All") }
    var favorites by rememberSaveable { mutableStateOf(false) }
    var sort by rememberSaveable { mutableStateOf("Newest") }
    val filtered = model.pieces.filter { p ->
        (category == "All" || p.category == category) && (!favorites || p.favorite) &&
            (search.isBlank() || (p.fields.values.joinToString(" ") + p.name).contains(search, ignoreCase = true))
    }.let { list -> when(sort) { "Name" -> list.sortedBy { it.name.lowercase() }; "Oldest" -> list.sortedBy { it.created }; else -> list } }
    Column(Modifier.fillMaxSize()) {
        Text("A little order. A lot more possibility.", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 20.dp))
        OutlinedTextField(search, { search = it }, placeholder = { Text("Search pieces, colors, tags…") }, leadingIcon = { Icon(Icons.Outlined.Search, null) }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(16.dp))
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            (listOf("All") + categories).forEach { label -> FilterChip(category == label, { category = label }, label = { Text(label) }) }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            FilterChip(favorites, { favorites = !favorites }, label = { Text("Favorites") }, leadingIcon = { Icon(Icons.Outlined.FavoriteBorder, null, Modifier.size(16.dp)) })
            Spacer(Modifier.weight(1f))
            var expanded by remember { mutableStateOf(false) }
            Box {
                TextButton(onClick = { expanded = true }) { Text(sort); Icon(Icons.Outlined.ExpandMore, null) }
                DropdownMenu(expanded, { expanded = false }) { listOf("Newest", "Oldest", "Name").forEach { label -> DropdownMenuItem(text = { Text(label) }, onClick = { sort = label; expanded = false }) } }
            }
        }
        if(filtered.isEmpty()) Column(Modifier.fillMaxWidth().weight(1f).padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Icon(Icons.Outlined.Checkroom, null, Modifier.size(64.dp), tint = MaterialTheme.colorScheme.primary)
            Text(if(model.pieces.isEmpty()) "Make room for your wardrobe" else "No matching pieces", fontFamily = FontFamily.Serif, fontSize = 26.sp, modifier = Modifier.padding(vertical = 16.dp))
            Text(if(model.pieces.isEmpty()) "Start with a photo of something you love. Your pieces stay on this device, ready whenever you are." else "Try a different search or filter.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            if(model.pieces.isEmpty()) Button(onClick = add, modifier = Modifier.padding(top = 24.dp)) { Text("Add your first piece") }
        } else LazyVerticalGrid(columns = GridCells.Adaptive(155.dp), contentPadding = PaddingValues(16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            items(filtered, key = { it.id }) { piece -> Column(Modifier.clickable { open(piece.id) }) {
                Box {
                    PieceImage(model, piece.cover, piece.name, Modifier.fillMaxWidth().aspectRatio(0.8f))
                    if(piece.favorite) Icon(Icons.Outlined.Favorite, "Favorite", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.align(Alignment.TopEnd).padding(10.dp))
                }
                Text(piece.name, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 10.dp))
                Text(listOf(piece.fields["color"].orEmpty(), piece.fields["subcategory"].orEmpty().ifBlank { piece.category }).filter { it.isNotBlank() }.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if(piece.state == "preparing") Text("Preparing…", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelSmall)
            } }
        }
    }
}

@Composable
fun AddScreen(model: DrapeModel, done: (String) -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(6)) { model.importPhotos(it) }
    var cameraPath by rememberSaveable { mutableStateOf<String?>(null) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        cameraPath?.let { path -> if(success) model.importPhotos(listOf(android.net.Uri.fromFile(File(path)))) }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Every piece has a place.", fontFamily = FontFamily.Serif, fontSize = 28.sp)
        Text("Add a whole-piece photo first, then labels or extra angles. Up to six photos.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !model.busy && model.draft.size < 6, modifier = Modifier.weight(1f)) { Icon(Icons.Outlined.PhotoLibrary, null); Spacer(Modifier.width(8.dp)); Text("Photos") }
            OutlinedButton(onClick = {
                val file = File(context.cacheDir, "capture/${java.util.UUID.randomUUID()}.jpg").apply { parentFile?.mkdirs(); createNewFile() }
                cameraPath = file.absolutePath
                try { camera.launch(FileProvider.getUriForFile(context, "${context.packageName}.photos", file)) }
                catch (_: Exception) { model.error = "A camera app could not be opened. You can choose a photo instead." }
            }, enabled = !model.busy && model.draft.size < 6, modifier = Modifier.weight(1f)) { Icon(Icons.Outlined.PhotoCamera, null); Spacer(Modifier.width(8.dp)); Text("Camera") }
        }
        model.draft.forEachIndexed { index, bytes ->
            Column {
                AsyncImage(model = bytes, contentDescription = "Selected photo ${index + 1}", contentScale = ContentScale.Fit, modifier = Modifier.fillMaxWidth().height(if(index == 0) 270.dp else 180.dp).background(Color.White, RoundedCornerShape(16.dp)))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(if(index == 0) "Whole piece" else "Detail ${index}", Modifier.weight(1f))
                    TextButton(onClick = { model.removeDraft(index) }, enabled = !model.busy) { Text("Remove") }
                }
            }
        }
        if(model.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        Text("Add to wardrobe sends these photos to Drape’s AI service and its providers to identify the piece and create a studio photo. Originals are kept. AI can make mistakes.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Button(onClick = { model.add(true, done) }, enabled = model.draft.isNotEmpty() && !model.busy && model.ai.available, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text("Add to wardrobe") }
        OutlinedButton(onClick = { model.add(false, done) }, enabled = model.draft.isNotEmpty() && !model.busy, modifier = Modifier.fillMaxWidth()) { Text("Save photos only") }
        Text("Save photos only works offline and does not upload anything.", style = MaterialTheme.typography.bodySmall)
        if(!model.ai.available) Text("AI preparation is unavailable in this build. You can still save and edit your wardrobe.", style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
fun DetailScreen(model: DrapeModel, piece: Piece, back: () -> Unit) {
    var editing by rememberSaveable(piece.id) { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var photoIndex by rememberSaveable(piece.id) { mutableIntStateOf(0) }
    val photos = listOfNotNull(piece.studio) + piece.photos
    if(editing) { EditScreen(model, piece) { editing = false }; return }
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            PieceImage(model, photos[photoIndex.coerceIn(photos.indices)], piece.name, Modifier.fillMaxWidth().height(350.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) { photos.forEachIndexed { i, _ ->
                FilterChip(photoIndex == i, { photoIndex = i }, label = { Text(if(piece.studio != null && i == 0) "Studio" else "Original ${i + if(piece.studio == null) 1 else 0}") })
            } }
            if(piece.studio != null) {
                Text("AI studio photo — compare with the original for accuracy.", style = MaterialTheme.typography.bodySmall)
                TextButton(onClick = { model.cover(piece.id, !piece.useStudio) }) { Text(if(piece.useStudio) "Use original as cover" else "Use studio as cover") }
            }
        }
        item { Row(verticalAlignment = Alignment.CenterVertically) {
            Text(piece.name, fontFamily = FontFamily.Serif, fontSize = 28.sp, modifier = Modifier.weight(1f))
            IconButton(onClick = { model.favorite(piece.id) }) { Icon(if(piece.favorite) Icons.Outlined.Favorite else Icons.Outlined.FavoriteBorder, if(piece.favorite) "Remove favorite" else "Add favorite", tint = MaterialTheme.colorScheme.primary) }
        } }
        item { OutlinedButton(onClick = { editing = true }, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Outlined.Edit, null); Spacer(Modifier.width(8.dp)); Text("Edit details") } }
        if(piece.state == "preparing") item { LinearProgressIndicator(Modifier.fillMaxWidth()); Text("Preparing your piece. You can keep browsing.", Modifier.padding(top = 8.dp)) }
        else if(!piece.complete) item {
            Text(if(piece.analyzed) "Details are saved. Your studio photo is still unfinished." else "Your photos are saved. Details and a studio photo can be prepared when you’re ready.")
            Text("Finish preparing uploads the original photos for unfinished AI steps. Completed steps won’t run again.", style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(vertical = 10.dp))
            Button(onClick = { model.prepare(piece.id) }, enabled = model.ai.available, modifier = Modifier.fillMaxWidth()) { Text("Finish preparing") }
        }
        items(editableFields.filter { it != "name" && !piece.fields[it].isNullOrBlank() }) { field ->
            Column {
                Text(fieldLabel(field), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(piece.fields.getValue(field) + if(field == "condition" && piece.fields["conditionSource"] == "photo") " · AI estimate" else "")
                val evidence = when(field) { "price" -> piece.fields["priceEvidence"]; "condition" -> piece.fields["conditionEvidence"]; else -> null }
                if(!evidence.isNullOrBlank()) Text(evidence, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item { TextButton(onClick = { deleting = true }) { Icon(Icons.Outlined.DeleteOutline, null); Text("Delete piece") } }
    }
    if(deleting) AlertDialog(onDismissRequest = { deleting = false }, title = { Text("Delete this piece?") }, text = { Text("Its photos and details will be removed from this device and from your looks.") }, confirmButton = { TextButton(onClick = { model.delete(piece.id, back) }) { Text("Delete") } }, dismissButton = { TextButton(onClick = { deleting = false }) { Text("Keep piece") } })
}
fun fieldLabel(key: String) = when(key) { "subcategory" -> "Item type"; "typeDetail" -> "Specific style"; "price" -> "Original price"; "currency" -> "Currency (EUR, USD…)"; "tags" -> "Tags, separated by commas"; else -> key.replaceFirstChar { it.uppercase() } }

@Composable
fun ChoiceField(label: String, selected: String, options: List<String>, changed: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Column { Text(label, style = MaterialTheme.typography.labelMedium); Box {
        OutlinedButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) { Text(selected.ifBlank { "Not specified" }, Modifier.weight(1f)); Icon(Icons.Outlined.ExpandMore, null) }
        DropdownMenu(expanded, { expanded = false }) { options.forEach { value -> DropdownMenuItem(text = { Text(value.ifBlank { "Not specified" }) }, onClick = { changed(value); expanded = false }) } }
    } }
}
@Composable
fun EditScreen(model: DrapeModel, piece: Piece, done: () -> Unit) {
    val mapState = mapSaver<Map<String, String>>(
        save = { it }, restore = { values -> values.mapValues { it.value as String } }
    )
    val baseline = rememberSaveable(piece.id, saver = mapState) { piece.fields.toMap() }
    var fields by rememberSaveable(piece.id, stateSaver = mapState) { mutableStateOf(editableFields.associateWith { piece.fields[it].orEmpty() }) }
    BackHandler { done() }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = done) { Text("Cancel") }
            Button(onClick = { model.edit(piece.id, baseline, fields, done) }) { Text("Save details") }
        }
        LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            items(editableFields) { field ->
                val update: (String) -> Unit = { fields = fields + (field to it) }
                when(field) {
                    "category" -> ChoiceField("Category", fields[field].orEmpty(), categories) { fields = fields + mapOf("category" to it, "subcategory" to "", "typeDetail" to "") }
                    "subcategory" -> ChoiceField("Item type", fields[field].orEmpty(), listOf("") + taxonomy[fields["category"]].orEmpty(), update)
                    "condition" -> ChoiceField("Condition", fields[field].orEmpty(), listOf("", "Excellent", "Very good", "Good", "Fair", "Poor"), update)
                    else -> OutlinedTextField(fields[field].orEmpty(), update, label = { Text(fieldLabel(field)) }, modifier = Modifier.fillMaxWidth(), minLines = if(field == "notes") 3 else 1)
                }
            }
        }
    }
}

@Composable
fun LooksScreen(model: DrapeModel, open: (String) -> Unit) {
    var adding by rememberSaveable { mutableStateOf(false) }
    var name by rememberSaveable { mutableStateOf("") }
    var selected by remember { mutableStateOf(setOf<String>()) }
    var deleting by remember { mutableStateOf<Look?>(null) }
    if(adding) {
        BackHandler { adding = false }
        Column(Modifier.fillMaxSize().padding(20.dp)) {
            OutlinedTextField(name, { name = it }, label = { Text("Look name") }, modifier = Modifier.fillMaxWidth())
            Row { TextButton(onClick = { adding = false }) { Text("Cancel") }; Spacer(Modifier.weight(1f)); Button(onClick = { model.saveLook(name, selected.toList()) { adding = false; name = ""; selected = emptySet() } }, enabled = name.isNotBlank() && selected.isNotEmpty()) { Text("Save look") } }
            LazyColumn { items(model.pieces, key = { it.id }) { p -> Row(Modifier.fillMaxWidth().clickable { selected = if(p.id in selected) selected - p.id else selected + p.id }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                PieceImage(model, p.cover, p.name, Modifier.size(72.dp)); Text(p.name, Modifier.weight(1f).padding(12.dp)); Checkbox(p.id in selected, null)
            } } }
        }
    } else LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        item { Text("Pieces that belong together.", fontFamily = FontFamily.Serif, fontSize = 26.sp); Text("Save combinations from your own wardrobe.", Modifier.padding(vertical = 12.dp)); Button(onClick = { adding = true }, enabled = model.pieces.isNotEmpty()) { Text("Create a look") } }
        if(model.looks.isEmpty()) item { Text("Your saved looks will appear here. Add a few pieces to get started.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        items(model.looks, key = { it.id }) { look -> Column {
            Row(verticalAlignment = Alignment.CenterVertically) { Text(look.name, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f)); IconButton(onClick = { deleting = look }) { Icon(Icons.Outlined.DeleteOutline, "Delete look") } }
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) { look.ids.mapNotNull { id -> model.pieces.find { it.id == id } }.forEach { p -> PieceImage(model, p.cover, p.name, Modifier.size(140.dp).clickable { open(p.id) }) } }
        } }
    }
    deleting?.let { look -> AlertDialog(onDismissRequest = { deleting = null }, title = { Text("Delete ${look.name}?") }, text = { Text("The pieces in this look will stay in your wardrobe.") }, confirmButton = { TextButton(onClick = { model.deleteLook(look.id); deleting = null }) { Text("Delete look") } }, dismissButton = { TextButton(onClick = { deleting = null }) { Text("Cancel") } }) }
}

@Composable
fun SettingsScreen(model: DrapeModel) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { it?.let(model::export) }
    val restore = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { it?.let(model::restore) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Text("Yours, on this device.", fontFamily = FontFamily.Serif, fontSize = 28.sp)
        Text("Your wardrobe is stored on this phone. Drape has no account, cloud wardrobe sync, ads, or analytics. Uninstalling the app removes its local wardrobe.")
        HorizontalDivider()
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) { Text("Device lock", style = MaterialTheme.typography.titleMedium); Text("Require your phone’s PIN, pattern or password when you return.", style = MaterialTheme.typography.bodySmall) }
            Switch(model.lockEnabled, { enabled ->
                val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                if(enabled && !keyguard.isDeviceSecure) model.error = "Set up a screen lock in Android Settings first."
                else model.setLock(enabled)
            })
        }
        HorizontalDivider()
        Text("Keep a copy", style = MaterialTheme.typography.titleLarge)
        Text("Export an Android wardrobe backup before moving phones or uninstalling. Backups include your photos and may sync through the file provider you choose. Import merges missing pieces; existing pieces are kept. Android backups currently import into Android only. Maximum backup size: 100 MB.", style = MaterialTheme.typography.bodySmall)
        OutlinedButton(onClick = { export.launch("Drape-wardrobe.json") }, enabled = !model.busy, modifier = Modifier.fillMaxWidth()) { Text("Export wardrobe") }
        OutlinedButton(onClick = { restore.launch(arrayOf("application/json", "application/octet-stream")) }, enabled = !model.busy, modifier = Modifier.fillMaxWidth()) { Text("Import Android backup") }
        if(model.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        HorizontalDivider()
        Text("Photo privacy & AI", style = MaterialTheme.typography.titleLarge)
        Text("Save photos only stays offline. Add to wardrobe and Finish preparing explicitly send your selected photos to the Drape gateway, OpenRouter, and its model providers. Photo metadata is stripped before storage and upload. No photos are uploaded just by opening the app.")
        Text("AI can be wrong. Check labels for size, materials and care. Condition is a visual estimate; prices are reported only from legible evidence. Compare generated studio photos with your originals.")
        TextButton(onClick = { context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse("https://openrouter.ai/privacy"))) }) { Text("OpenRouter privacy policy") }
        Text("Drape for Android · ${BuildConfig.VERSION_NAME}", style = MaterialTheme.typography.labelMedium)
    }
}
