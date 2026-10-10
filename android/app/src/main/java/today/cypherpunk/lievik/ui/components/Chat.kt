package today.cypherpunk.lievik.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import today.cypherpunk.lievik.R

data class ChatMessage(val role: String, val content: String, val streaming: Boolean = false, val error: Boolean = false)

@Composable
fun ChatBubble(
    message: ChatMessage,
    thinking: String,
    modifier: Modifier = Modifier,
    onCitation: ((Long) -> Unit)? = null,
    footer: @Composable () -> Unit = {},
) {
    val mine = message.role == "user"
    Box(modifier.fillMaxWidth(), contentAlignment = if (mine) Alignment.CenterEnd else Alignment.CenterStart) {
        Surface(
            color = when {
                message.error -> MaterialTheme.colorScheme.errorContainer
                mine -> MaterialTheme.colorScheme.primaryContainer
                else -> MaterialTheme.colorScheme.surface
            },
            shape = RoundedCornerShape(14.dp),
            tonalElevation = if (mine) 0.dp else 1.dp,
            modifier = Modifier.widthIn(max = 640.dp),
        ) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                when {
                    message.content.isEmpty() && message.streaming -> Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        Text(thinking, modifier = Modifier.padding(start = 8.dp), style = MaterialTheme.typography.bodyMedium)
                    }
                    mine || message.error -> Text(message.content, style = MaterialTheme.typography.bodyMedium)
                    else -> MarkdownText(message.content, onCitation = onCitation)
                }
                footer()
            }
        }
    }
}

@Composable
fun ChatInput(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    streaming: Boolean,
    onSend: () -> Unit,
    onStop: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value, onValueChange,
            placeholder = { Text(placeholder) },
            maxLines = 5,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { if (!streaming && value.isNotBlank()) onSend() }),
            modifier = Modifier.weight(1f),
        )
        if (streaming) {
            FilledIconButton(onClick = onStop, modifier = Modifier.size(52.dp)) {
                Icon(Icons.Filled.Stop, contentDescription = stringResource(R.string.stop))
            }
        } else {
            FilledIconButton(onClick = onSend, enabled = value.isNotBlank(), modifier = Modifier.size(52.dp)) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = stringResource(R.string.ai_send))
            }
        }
    }
}
