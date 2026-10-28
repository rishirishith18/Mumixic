package com.music.bitchord.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Large, horizontally browsed pivot titles inspired by Windows Phone navigation. */
@Composable
fun WindowsPhoneTabSwitcher(
    tabs: List<BottomTab>,
    selectedIndex: Int,
    onTabSelected: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()
    LaunchedEffect(selectedIndex) {
        if (selectedIndex in tabs.indices) listState.animateScrollToItem(selectedIndex)
    }
    LazyRow(
        state = listState,
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 24.dp, end = 24.dp),
        horizontalArrangement = Arrangement.spacedBy(28.dp),
    ) {
        itemsIndexed(tabs) { index, tab ->
            val selected = index == selectedIndex
            Column(
                modifier = Modifier
                    .clickable { onTabSelected(index) }
                    .padding(top = 2.dp, bottom = 6.dp),
            ) {
                Text(
                    text = tab.label.uppercase(),
                    style = MaterialTheme.typography.displaySmall.copy(
                        fontSize = 36.sp,
                        fontWeight = if (selected) FontWeight.Black else FontWeight.ExtraBold,
                        letterSpacing = 0.5.sp,
                    ),
                    color = MaterialTheme.colorScheme.onBackground.copy(
                        alpha = if (selected) 1f else 0.45f,
                    ),
                    maxLines = 1,
                    overflow = TextOverflow.Clip,
                )
                Spacer(Modifier.height(4.dp))
                Box(
                    Modifier
                        .width(if (selected) 42.dp else 0.dp)
                        .height(3.5.dp)
                        .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(2.dp)),
                )
            }
        }
    }
}
