package dev.lvtd.drape

import android.content.Context
import android.util.Base64
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class WardrobeAI(
    private val context: Context,
    private val client: OkHttpClient = defaultClient(),
    private val baseURL: String = BuildConfig.AI_URL,
    private val credential: String = BuildConfig.AI_TOKEN
) {
    companion object {
        fun defaultClient() = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(150, TimeUnit.SECONDS).callTimeout(180, TimeUnit.SECONDS)
        .retryOnConnectionFailure(false).followRedirects(false).followSslRedirects(false).build()
    }
    val available get() = BuildConfig.DEBUG && baseURL.startsWith("https://") && credential.isNotBlank()
    private fun asset(name: String) = context.assets.open(name).bufferedReader().use { it.readText() }
    private fun dataURL(bytes: ByteArray) = "data:image/jpeg;base64," + Base64.encodeToString(bytes, Base64.NO_WRAP)
    private fun post(path: String, json: JSONObject): JSONObject {
        check(available) { "AI preparation is unavailable in this build. Your photos are saved." }
        val payload = json.toString().toByteArray(Charsets.UTF_8)
        require(payload.size <= 12_000_000) { "These photos are too large to prepare together." }
        val request = Request.Builder().url(baseURL.trimEnd('/') + "/" + path)
            .header("Authorization", "Bearer ${credential}")
            .header("X-OpenRouter-Title", "Drape")
            .post(payload.toRequestBody("application/json".toMediaType())).build()
        client.newCall(request).execute().use { response ->
            check(response.isSuccessful) { "AI preparation could not finish (${response.code}). Your photos are saved. You can finish later." }
            val body = requireNotNull(response.body)
            val bytes = body.byteStream().use { it.readBytesLimited(40_000_000) }
            return JSONObject(String(bytes, Charsets.UTF_8))
        }
    }
    fun analyze(photos: List<ByteArray>): Map<String, String> {
        val content = JSONArray().put(JSONObject().put("type", "text").put("text", asset("analysis-prompt.txt")))
        photos.forEach { content.put(JSONObject().put("type", "image_url").put("image_url", JSONObject().put("url", dataURL(it)))) }
        val body = JSONObject().put("model", "openai/gpt-6-luna")
            .put("messages", JSONArray().put(JSONObject().put("role", "user").put("content", content)))
            .put("max_tokens", 1800).put("provider", JSONObject().put("require_parameters", true).put("data_collection", "deny"))
            .put("response_format", JSONObject().put("type", "json_schema").put("json_schema", JSONObject()
                .put("name", "wardrobe_item").put("strict", true).put("schema", JSONObject(asset("analysis-schema.json")))))
        val response = post("chat/completions", body)
        val result = JSONObject(response.getJSONArray("choices").getJSONObject(0).getJSONObject("message").getString("content"))
        val details = result.getJSONObject("details")
        require(details.getString("category") in categories)
        val fields = detailFields.associateWith { details.getString(it) }.toMutableMap()
        val attrs = result.getJSONObject("attributes")
        fields["typeDetail"] = attrs.getString("typeDetail")
        fields["tags"] = attrs.getJSONArray("tags").strings().map { it.trim().lowercase() }.distinct().joinToString(", ")
        attrs.optJSONObject("originalPrice")?.let {
            require(it.getString("source") == "photo" && it.getString("evidence").isNotBlank())
            require(it.getString("amount").matches(Regex("(0|[1-9][0-9]{0,11})(\\.[0-9]{1,4})?")))
            java.util.Currency.getInstance(it.getString("currency"))
            fields["price"] = it.getString("amount"); fields["currency"] = it.getString("currency")
            fields["priceEvidence"] = it.getString("evidence"); fields["priceSource"] = "photo"
        }
        attrs.optJSONObject("condition")?.let {
            require(it.getString("source") == "photo" && it.getString("evidence").isNotBlank())
            require(it.getString("grade") in listOf("Excellent", "Very good", "Good", "Fair", "Poor"))
            fields["condition"] = it.getString("grade"); fields["conditionEvidence"] = it.getString("evidence"); fields["conditionSource"] = "photo"
        }
        return fields
    }
    fun studio(front: ByteArray): ByteArray {
        val body = JSONObject().put("model", "bytedance-seed/seedream-5-0-flash").put("prompt", asset("studio-prompt.txt"))
            .put("input_references", JSONArray().put(JSONObject().put("type", "image_url").put("image_url", JSONObject().put("url", dataURL(front)))))
            .put("n", 1).put("resolution", "1K").put("aspect_ratio", "3:4")
        val base64 = post("images", body).getJSONArray("data").getJSONObject(0).getString("b64_json")
        return Photos.normalize(Base64.decode(base64, Base64.DEFAULT))
    }
}
fun java.io.InputStream.readBytesLimited(limit: Int): ByteArray {
    val output = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(8192)
    while(true) { val n = read(buffer); if(n < 0) break; require(output.size() + n <= limit) { "This file is too large." }; output.write(buffer, 0, n) }
    return output.toByteArray()
}
