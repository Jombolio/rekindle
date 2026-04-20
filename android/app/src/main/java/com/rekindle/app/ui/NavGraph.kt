package com.rekindle.app.ui

import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.rekindle.app.domain.model.Media
import com.rekindle.app.ui.screens.ChapterIndexScreen
import com.rekindle.app.ui.screens.EpubReaderScreen
import com.rekindle.app.ui.screens.LibraryScreen
import com.rekindle.app.ui.screens.LoginScreen
import com.rekindle.app.ui.screens.MediaGridScreen
import com.rekindle.app.ui.screens.ReaderScreen
import com.rekindle.app.ui.screens.SettingsScreen

sealed class Screen(val route: String) {
    data object Login : Screen("login")
    data object Libraries : Screen("libraries")
    data object Settings : Screen("settings")
    data object MediaGrid : Screen("library/{libraryId}?name={libraryName}") {
        fun route(libraryId: String, name: String? = null) =
            "library/$libraryId?name=${encode(name)}"
    }
    data object Series : Screen("series/{folderId}?title={title}") {
        fun route(folderId: String, title: String? = null) =
            "series/$folderId?title=${encode(title)}"
    }
    data object Reader : Screen("reader/{mediaId}") {
        fun route(mediaId: String) = "reader/$mediaId"
    }
    data object Epub : Screen("epub/{mediaId}?title={title}") {
        fun route(mediaId: String, title: String? = null) =
            "epub/$mediaId?title=${encode(title)}"
    }

    companion object {
        private fun encode(s: String?) = java.net.URLEncoder.encode(s ?: "", "UTF-8")
    }
}

fun Media.openRoute(): String = when {
    isFolder -> Screen.Series.route(id, displayTitle)
    isImageBased -> Screen.Reader.route(id)
    else -> Screen.Epub.route(id, displayTitle)
}

@Composable
fun RekindleApp() {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = Screen.Login.route) {

        composable(Screen.Login.route) {
            LoginScreen(onLoginSuccess = {
                navController.navigate(Screen.Libraries.route) {
                    popUpTo(Screen.Login.route) { inclusive = true }
                }
            })
        }

        composable(Screen.Libraries.route) {
            LibraryScreen(
                onLibraryClick = { id, name ->
                    navController.navigate(Screen.MediaGrid.route(id, name))
                },
                onSettingsClick = { navController.navigate(Screen.Settings.route) },
                onLogout = {
                    navController.navigate(Screen.Login.route) {
                        popUpTo(0) { inclusive = true }
                    }
                },
            )
        }

        composable(
            route = Screen.MediaGrid.route,
            arguments = listOf(
                navArgument("libraryId") { type = NavType.StringType },
                navArgument("libraryName") { type = NavType.StringType; defaultValue = "" },
            ),
        ) { back ->
            val libraryId = back.arguments!!.getString("libraryId")!!
            val libraryName = back.arguments!!.getString("libraryName")?.decode()
            MediaGridScreen(
                libraryId = libraryId,
                libraryName = libraryName?.ifBlank { null },
                onItemClick = { media -> navController.navigate(media.openRoute()) },
                onBack = { navController.popBackStack() },
            )
        }

        composable(
            route = Screen.Series.route,
            arguments = listOf(
                navArgument("folderId") { type = NavType.StringType },
                navArgument("title") { type = NavType.StringType; defaultValue = "" },
            ),
        ) { back ->
            val folderId = back.arguments!!.getString("folderId")!!
            val title = back.arguments!!.getString("title")?.decode()
            ChapterIndexScreen(
                folderId = folderId,
                title = title?.ifBlank { null },
                onChapterClick = { media -> navController.navigate(media.openRoute()) },
                onBack = { navController.popBackStack() },
            )
        }

        composable(
            route = Screen.Reader.route,
            arguments = listOf(navArgument("mediaId") { type = NavType.StringType }),
        ) { back ->
            ReaderScreen(
                mediaId = back.arguments!!.getString("mediaId")!!,
                onBack = { navController.popBackStack() },
            )
        }

        composable(
            route = Screen.Epub.route,
            arguments = listOf(
                navArgument("mediaId") { type = NavType.StringType },
                navArgument("title") { type = NavType.StringType; defaultValue = "" },
            ),
        ) { back ->
            val mediaId = back.arguments!!.getString("mediaId")!!
            val title = back.arguments!!.getString("title")?.decode() ?: ""
            EpubReaderScreen(
                mediaId = mediaId,
                title = title,
                onBack = { navController.popBackStack() },
            )
        }

        composable(Screen.Settings.route) {
            SettingsScreen(onBack = { navController.popBackStack() })
        }
    }
}

private fun String.decode(): String =
    java.net.URLDecoder.decode(this, "UTF-8")
