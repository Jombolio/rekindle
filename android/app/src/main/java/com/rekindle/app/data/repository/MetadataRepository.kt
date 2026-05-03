package com.rekindle.app.data.repository

import com.rekindle.app.data.api.RekindleApi
import com.rekindle.app.data.model.SetMetadataConfigRequest
import com.rekindle.app.data.model.toDomain
import com.rekindle.app.domain.model.MangaMetadata
import com.rekindle.app.domain.model.MetadataConfig
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MetadataRepository @Inject constructor(private val api: RekindleApi) {

    suspend fun getMetadata(mediaId: String): MangaMetadata? = try {
        api.getMetadata(mediaId).toDomain()
    } catch (_: Exception) {
        null
    }

    suspend fun scrapeMetadata(mediaId: String): MangaMetadata =
        api.scrapeMetadata(mediaId).toDomain()

    suspend fun getConfig(): MetadataConfig =
        api.getMetadataConfig().toDomain()

    suspend fun saveConfig(malClientId: String? = null, comicvineApiKey: String? = null) =
        api.setMetadataConfig(SetMetadataConfigRequest(
            malClientId = malClientId,
            comicvineApiKey = comicvineApiKey,
        ))
}
