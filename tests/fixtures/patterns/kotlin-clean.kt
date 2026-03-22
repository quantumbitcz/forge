package com.example.core.domain

import kotlin.uuid.Uuid
import kotlinx.datetime.Instant

data class CleanDomain(
    val id: Uuid,
    val name: String,
    val createdAt: Instant
)
