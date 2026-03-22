package com.example.core.domain

import java.util.UUID
import org.springframework.data.annotation.Id

class BadDomain {
    val id = UUID.randomUUID()!!
    fun doWork() {
        Thread.sleep(1000)
        println("debug output")
        throw RuntimeException("oops")
    }
    val password = "supersecret123"
}
