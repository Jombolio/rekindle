package com.rekindle.app.ui

import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import androidx.compose.animation.core.tween
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.rekindle.app.domain.model.Media
import com.rekindle.app.ui.screens.AdminScreen
import com.rekindle.app.ui.screens.ChapterIndexScreen
import com.rekindle.app.ui.screens.EpubReaderScreen
import com.rekindle.app.ui.screens.LibraryScreen
import com.rekindle.app.ui.screens.LoginScreen
import com.rekindle.app.ui.screens.MediaGridScreen
import com.rekindle.app.ui.screens.ReaderScreen
import com.rekindle.app.ui.screens.SettingsScreen
import com.rekindle.app.ui.viewmodel.MainViewModel

sealed class Screen(val route: String) {
    data object Login : Screen("login")
    data object Libraries : Screen("libraries")
    data object Settings : Screen("settings")
    data object Admin : Screen("admin")
    data object MediaGrid : Screen("library/{libraryId}?name={libraryName}&libraryType={libraryType}") {
        fun route(libraryId: String, name: String? = null, libraryType: String? = null) =
            "library/$libraryId?name=${encode(name)}&libraryType=${encode(libraryType)}"
    }
    data object Series : Screen("series/{folderId}?title={title}&libraryType={libraryType}") {
        fun route(folderId: String, title: String? = null, libraryType: String? = null) =
            "series/$folderId?title=${encode(title)}&libraryType=${encode(libraryType)}"
    }
    data object Reader : Screen("reader/{mediaId}?initialPage={initialPage}&libraryType={libraryType}") {
        fun route(mediaId: String, initialPage: Int = -1, libraryType: String? = null) =
            "reader/$mediaId?initialPage=$initialPage&libraryType=${encode(libraryType)}"
    }
    data object Epub : Screen("epub/{mediaId}?title={title}") {
        fun route(mediaId: String, title: String? = null) =
            "epub/$mediaId?title=${encode(title)}"
    }

    companion object {
        private fun encode(s: String?) = java.net.URLEncoder.encode(s ?: "", "UTF-8")
    }
}

fun Media.openRoute(libraryType: String? = null): String = when {
    isFolder -> Screen.Series.route(id, displayTitle, libraryType)
    isImageBased -> Screen.Reader.route(id, libraryType = libraryType)
    else -> Screen.Epub.route(id, displayTitle)
}

@Composable
fun RekindleApp(vm: MainViewModel = hiltViewModel()) {
    val startDestination by vm.startDestination.collectAsState()

    // Hold an invisible placeholder while DataStore resolves the start route
    // (typically < 100 ms — imperceptible to the user).
    if (startDestination == null) {
        Box(modifier = Modifier.fillMaxSize())
        return
    }

    val navController = rememberNavController()
    val scope = rememberCoroutineScope()
    var blockInput by remember { mutableStateOf(false) }

    // When a 401 clears the active source's token at runtime, pop everything
    // back to Libraries so the sign-in prompt is shown for that source.
    LaunchedEffect(Unit) {
        vm.tokenLost.collect {
            navController.navigate(Screen.Libraries.route) {
                popUpTo(0) { inclusive = false }
            }
        }
    }

    // Block all touch input for the duration of each transition to prevent
    // mis-taps landing on the incoming screen before it is fully visible.
    LaunchedEffect(navController) {
        navController.addOnDestinationChangedListener { _, _, _ ->
            blockInput = true
            scope.launch {
                delay(150L)
                blockInput = false
            }
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
    NavHost(
        navController = navController,
        startDestination = startDestination!!,
        enterTransition = { fadeIn(animationSpec = tween(150)) },
        exitTransition = { fadeOut(animationSpec = tween(150)) },
        popEnterTransition = { fadeIn(animationSpec = tween(150)) },
        popExitTransition = { fadeOut(animationSpec = tween(150)) },
    ) {

        composable(Screen.Login.route) {
            LoginScreen(onLoginSuccess = {
                navController.navigate(Screen.Libraries.route) {
                    popUpTo(Screen.Login.route) { inclusive = true }
                }
            })
        }

        composable(Screen.Libraries.route) {
            LibraryScreen(
                onLibraryClick = { id, name, type ->
                    navController.navigate(Screen.MediaGrid.route(id, name, type))
                },
                onSettingsClick = { navController.navigate(Screen.Settings.route) },
                onAdminClick = { navController.navigate(Screen.Admin.route) },
                onAddSource = { navController.navigate(Screen.Login.route) },
            )
        }

        composable(
            route = Screen.MediaGrid.route,
            arguments = listOf(
                navArgument("libraryId") { type = NavType.StringType },
                navArgument("libraryName") { type = NavType.StringType; defaultValue = "" },
                navArgument("libraryType") { type = NavType.StringType; defaultValue = "" },
            ),
        ) { back ->
            val libraryId = back.arguments!!.getString("libraryId")!!
            val libraryName = back.arguments!!.getString("libraryName")?.decode()
            val libraryType = back.arguments!!.getString("libraryType")?.decode()
            MediaGridScreen(
                libraryId = libraryId,
                libraryName = libraryName?.ifBlank { null },
                onItemClick = { media -> navController.navigate(media.openRoute(libraryType)) },
                onBack = { navController.popBackStack() },
            )
        }

        composable(
            route = Screen.Series.route,
            arguments = listOf(
                navArgument("folderId") { type = NavType.StringType },
                navArgument("title") { type = NavType.StringType; defaultValue = "" },
                navArgument("libraryType") { type = NavType.StringType; defaultValue = "" },
            ),
        ) { back ->
            val folderId = back.arguments!!.getString("folderId")!!
            val title = back.arguments!!.getString("title")?.decode()
            val libraryType = back.arguments!!.getString("libraryType")?.decode()
            ChapterIndexScreen(
                folderId = folderId,
                title = title?.ifBlank { null },
                onChapterClick = { media -> navController.navigate(media.openRoute(libraryType)) },
                onBack = { navController.popBackStack() },
            )
        }

        composable(
            route = Screen.Reader.route,
            arguments = listOf(
                navArgument("mediaId") { type = NavType.StringType },
                navArgument("initialPage") { type = NavType.IntType; defaultValue = -1 },
                navArgument("libraryType") { type = NavType.StringType; defaultValue = "" },
            ),
        ) { back ->
            val libraryType = back.arguments!!.getString("libraryType")?.decode()
            ReaderScreen(
                mediaId = back.arguments!!.getString("mediaId")!!,
                onBack = { navController.popBackStack() },
                onNavigateToChapter = { targetId, initialPage ->
                    navController.navigate(Screen.Reader.route(targetId, initialPage, libraryType)) {
                        popUpTo(Screen.Reader.route) { inclusive = true }
                    }
                },
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
            SettingsScreen(
                onBack = { navController.popBackStack() },
                onAddSource = { navController.navigate(Screen.Login.route) },
                onSourceSwitch = {
                    navController.navigate(Screen.Libraries.route) {
                        popUpTo(0) { inclusive = true }
                    }
                },
            )
        }

        composable(Screen.Admin.route) {
            AdminScreen(onBack = { navController.popBackStack() })
        }
    }

    // Transparent overlay that absorbs all touches during transitions.
    if (blockInput) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    awaitPointerEventScope {
                        while (true) {
                            awaitPointerEvent(PointerEventPass.Initial)
                                .changes.forEach { it.consume() }
                        }
                    }
                },
        )
    }
    } // end outer Box
}

private fun String.decode(): String =
    java.net.URLDecoder.decode(this, "UTF-8")
