package com.music.bitchord.ui.replay

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Shadow
import com.music.bitchord.sharedui.resources.*
import org.jetbrains.compose.resources.painterResource
import org.jetbrains.compose.resources.stringResource
import com.music.bitchord.ui.player.MeshGradientBackground
import com.music.bitchord.ui.player.rememberArtworkColors
import java.util.Locale

/**
 * A modern, artwork-tinted Replay membership card. Tapping it opens the chart
 * represented by the headline figure.
 */
@Composable
fun ReplayCreditCard(
    label: String,
    value: String,
    detail: String?,
    artworkUrl: String?,
    /** Whose card it is. Empty falls back to the localized listener label. */
    holder: String,
    /** `MM/YY`, or null when there is nothing to date it from. */
    memberSince: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = rememberArtworkColors(artworkUrl)
    Box(
        modifier = modifier
            .aspectRatio(CARD_RATIO)
            .shadow(16.dp, CardShape, clip = false)
            .clip(CardShape)
            .border(
                width = 1.dp,
                brush = Brush.linearGradient(
                    listOf(
                        Color.White.copy(alpha = 0.25f),
                        Color.White.copy(alpha = 0.08f),
                        Color.White.copy(alpha = 0.18f),
                    ),
                ),
                shape = CardShape,
            )
            .clickable(onClick = onClick),
    ) {
        // Background: Album/artist artwork with soft blur and mesh overlay
        if (artworkUrl != null) {
            coil3.compose.AsyncImage(
                model = artworkUrl,
                contentDescription = null,
                contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                modifier = Modifier
                    .fillMaxSize()
                    .blur(20.dp),
            )
        } else {
            MeshGradientBackground(
                palette = palette,
                trackKey = label,
                blurRadius = 36.dp,
                animated = false,
            )
        }

        // Contrast and vibrancy gradient scrim
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0.0f to Color.Black.copy(alpha = 0.35f),
                        0.50f to Color.Black.copy(alpha = 0.55f),
                        1.0f to Color.Black.copy(alpha = 0.85f),
                    ),
                ),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp, vertical = 18.dp),
        ) {
            // Top branding & category row: Mumixic logo cleanly displayed with NO BOX
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(
                        text = (detail ?: stringResource(Res.string.your_listening_experience)).uppercase(Locale.getDefault()),
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontSize = 11.sp,
                            fontWeight = FontWeight.W800,
                            letterSpacing = 1.2.sp,
                        ),
                        color = Color.White.copy(alpha = 0.80f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Spacer(Modifier.width(10.dp))
                // Clean Mumixic mark and brand title — NOT in a box
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(
                        painter = painterResource(Res.drawable.ic_logo),
                        contentDescription = "Mumixic",
                        tint = Color.White,
                        modifier = Modifier.size(20.dp),
                    )
                    Text(
                        text = "Mumixic",
                        style = MaterialTheme.typography.titleSmall.copy(
                            fontWeight = FontWeight.Bold,
                            fontSize = 13.5.sp,
                            letterSpacing = 0.4.sp,
                        ),
                        color = Color.White,
                    )
                }
            }

            Spacer(Modifier.weight(1f))

            // Hero statistic: monumental modern display typography
            Text(
                text = value,
                style = MaterialTheme.typography.displaySmall.copy(
                    fontSize = 36.sp,
                    lineHeight = 38.sp,
                    fontWeight = FontWeight.W900,
                    letterSpacing = (-1.2).sp,
                ),
                color = Color.White,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(3.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.titleMedium.copy(
                    fontSize = 15.sp,
                    fontWeight = FontWeight.W600,
                    letterSpacing = (-0.2).sp,
                ),
                color = Color.White.copy(alpha = 0.85f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )

            Spacer(Modifier.weight(0.9f))

            // Clean modern listener profile footer (not a credit card strip)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = holder.ifBlank { stringResource(Res.string.default_replay_holder) },
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontWeight = FontWeight.W700,
                        fontSize = 12.sp,
                    ),
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (memberSince != null) {
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = memberSince,
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontWeight = FontWeight.Normal,
                            fontSize = 11.sp,
                        ),
                        color = Color.White.copy(alpha = 0.65f),
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

/** Silver-foil gradient brush for embossed card lettering. */
private val PolishedInk: Brush = Brush.verticalGradient(
    colors = listOf(
        Color(0xFFE8E8E8),
        Color(0xFFFFFFFF),
        Color(0xFFB0B0B0),
    )
)

/** Subtle depth shadow that makes embossed text look pressed into the card. */
private val EmbossShadow = Shadow(
    color = Color(0x88000000),
    offset = Offset(0f, 1.5f),
    blurRadius = 2f,
)

/**
 * A line pressed into the card rather than printed on it.
 *
 * Monospaced and widely tracked because that is what a card embosser produces —
 * fixed-pitch dies on a fixed-pitch wheel — and it is more of the recognition
 * than the shadow is. The shadow supplies the rest: dark, offset down, under a
 * fill that is brightest at the top edge, which is a raised surface lit from
 * above.
 */
@Composable
private fun Embossed(text: String, size: TextUnit) {
    Text(
        text = text,
        style = TextStyle(
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.W600,
            fontSize = size,
            letterSpacing = 1.6.sp,
            brush = PolishedInk,
            shadow = EmbossShadow,
        ),
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
}

/**
 * A rank badge. Number one is the accent; the rest are quiet, because a chart
 * where every position shouts has no first place.
 */
@Composable
fun RankBadge(rank: Int, accent: Color, modifier: Modifier = Modifier) {
    Text(
        text = rank.toString(),
        style = if (rank == 1) {
            MaterialTheme.typography.titleLarge
        } else {
            MaterialTheme.typography.titleMedium
        },
        fontWeight = FontWeight.W800,
        color = if (rank == 1) accent else Color.White.copy(alpha = 0.45f),
        modifier = modifier.width(28.dp),
    )
}

/**
 * A stand-in cover for a row that has no artwork — a genre, which is a word
 * rather than a release. Its initial on a colour derived from the word itself,
 * so the same genre is the same colour every time the page is opened.
 */
@Composable
fun InitialTile(text: String, size: Dp, shape: Shape) {
    val hue = (text.hashCode().toFloat() % 360f + 360f) % 360f
    val color = Color.hsl(hue, 0.55f, 0.45f)
    Box(
        Modifier
            .size(size)
            .clip(shape)
            .background(Brush.linearGradient(listOf(color, color.copy(alpha = 0.55f)))),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text.take(1).uppercase(Locale.ROOT),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.W800,
            color = Color.White,
        )
    }
}

private val CardShape = RoundedCornerShape(26.dp)

/** Whose card it is when there is no signed-in account to name. */

/** Modern music recap showcase proportions. */
private const val CARD_RATIO = 1.36f
