package com.rekindle.app.data.repository

import com.rekindle.app.data.api.RekindleApi
import com.rekindle.app.data.model.MangaMetadataDto
import com.rekindle.app.data.model.SetMetadataConfigRequest
import com.rekindle.app.data.model.toDomain
import com.rekindle.app.data.model.toDto
import com.rekindle.app.domain.model.MangaMetadata
import com.rekindle.app.domain.model.MetadataConfig
import com.rekindle.app.domain.model.ScrapeResult
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MetadataRepository @Inject constructor(private val api: RekindleApi) {

    suspend fun getMetadata(mediaId: String): MangaMetadata? = try {
        api.getMetadata(mediaId).toDomain()
    } catch (_: Exception) {
        null
    }

    suspend fun scrapeMetadata(mediaId: String): ScrapeResult =
        api.scrapeMetadata(mediaId).toDomain()

    suspend fun commitMetadata(mediaId: String, metadata: MangaMetadata): MangaMetadata =
        api.commitMetadata(mediaId, metadata.toDto()).toDomain()

    suspend fun getConfig(): MetadataConfig =
        api.getMetadataConfig().toDomain()

    suspend fun saveConfig(malClientId: String? = null, comicvineApiKey: String? = null) =
        api.setMetadataConfig(SetMetadataConfigRequest(
            malClientId = malClientId,
            comicvineApiKey = comicvineApiKey,
        ))
}
