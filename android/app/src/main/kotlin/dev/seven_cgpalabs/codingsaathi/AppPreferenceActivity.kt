package dev.seven_cgpalabs.codingsaathi

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class AppPreferenceActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        supportFragmentManager
            .beginTransaction()
            .replace(android.R.id.content, AppPreferenceFragment())
            .commit()
    }
}
