package com.example.paywall

import android.app.Activity
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

/**
 * Main Paywall composable screen.
 * 
 * Features:
 * - Gradient header with feature highlights
 * - Package selection with animations
 * - Free trial badges
 * - Savings indicators
 * - Purchase button with loading state
 * - Restore purchases option
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallScreen(
    viewModel: PaywallViewModel,
    onDismiss: () -> Unit = {},
    onPurchaseSuccess: () -> Unit = {}
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    
    // Handle purchase results
    LaunchedEffect(Unit) {
        viewModel.purchaseResult.collect { result ->
            when (result) {
                is PurchaseResult.Success -> onPurchaseSuccess()
                is PurchaseResult.Cancelled -> { /* Stay on paywall */ }
                is PurchaseResult.Error -> { /* Show error via snackbar */ }
            }
        }
    }
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = { },
                navigationIcon = {
                    IconButton(onClick = { 
                        viewModel.onDismiss()
                        onDismiss() 
                    }) {
                        Icon(Icons.Default.Close, contentDescription = "Close")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent
                )
            )
        }
    ) { paddingValues ->
        when (val currentState = state) {
            is PaywallState.Loading -> {
                LoadingContent(modifier = Modifier.padding(paddingValues))
            }
            is PaywallState.Error -> {
                ErrorContent(
                    message = currentState.message,
                    onRetry = { viewModel.loadOfferings() },
                    modifier = Modifier.padding(paddingValues)
                )
            }
            is PaywallState.Ready -> {
                ReadyContent(
                    state = currentState,
                    onPackageSelected = viewModel::selectPackage,
                    onPurchase = { viewModel.purchase(context as Activity) },
                    onRestore = viewModel::restorePurchases,
                    modifier = Modifier.padding(paddingValues)
                )
            }
        }
    }
}

@Composable
private fun LoadingContent(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        CircularProgressIndicator()
    }
}

@Composable
private fun ErrorContent(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = "😕",
            fontSize = 48.sp
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = message,
            textAlign = TextAlign.Center,
            style = MaterialTheme.typography.bodyLarge
        )
        Spacer(modifier = Modifier.height(24.dp))
        Button(onClick = onRetry) {
            Text("Try Again")
        }
    }
}

@Composable
private fun ReadyContent(
    state: PaywallState.Ready,
    onPackageSelected: (PackageInfo) -> Unit,
    onPurchase: () -> Unit,
    onRestore: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
    ) {
        // Header with gradient
        PaywallHeader()
        
        Spacer(modifier = Modifier.height(24.dp))
        
        // Features list
        FeaturesList()
        
        Spacer(modifier = Modifier.height(24.dp))
        
        // Package options
        Column(
            modifier = Modifier.padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            state.packages.forEach { packageInfo ->
                PackageCard(
                    packageInfo = packageInfo,
                    isSelected = packageInfo == state.selectedPackage,
                    onSelect = { onPackageSelected(packageInfo) }
                )
            }
        }
        
        Spacer(modifier = Modifier.height(24.dp))
        
        // Purchase button
        Button(
            onClick = onPurchase,
            enabled = state.selectedPackage != null && !state.isPurchasing,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .height(56.dp),
            shape = RoundedCornerShape(16.dp)
        ) {
            if (state.isPurchasing) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    color = MaterialTheme.colorScheme.onPrimary,
                    strokeWidth = 2.dp
                )
            } else {
                val buttonText = state.selectedPackage?.let { pkg ->
                    if (pkg.hasFreeTrial) {
                        "Start ${pkg.freeTrialDuration} Free Trial"
                    } else {
                        "Subscribe for ${pkg.priceString}"
                    }
                } ?: "Select a Plan"
                Text(buttonText, fontWeight = FontWeight.Bold)
            }
        }
        
        Spacer(modifier = Modifier.height(12.dp))
        
        // Restore purchases
        TextButton(
            onClick = onRestore,
            enabled = !state.isPurchasing,
            modifier = Modifier.align(Alignment.CenterHorizontally)
        ) {
            Text("Restore Purchases")
        }
        
        // Legal text
        Text(
            text = "Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage in Account Settings.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp)
        )
    }
}

@Composable
private fun PaywallHeader() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(200.dp)
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        MaterialTheme.colorScheme.primary,
                        MaterialTheme.colorScheme.primaryContainer
                    )
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "🚀",
                fontSize = 64.sp
            )
            Text(
                text = "Unlock Premium",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onPrimary
            )
            Text(
                text = "Get unlimited access to all features",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.8f)
            )
        }
    }
}

@Composable
private fun FeaturesList() {
    val features = listOf(
        "Unlimited projects",
        "Advanced analytics",
        "Priority support",
        "No ads"
    )
    
    Column(
        modifier = Modifier.padding(horizontal = 24.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        features.forEach { feature ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    Icons.Default.CheckCircle,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp)
                )
                Text(
                    text = feature,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

@Composable
private fun PackageCard(
    packageInfo: PackageInfo,
    isSelected: Boolean,
    onSelect: () -> Unit
) {
    val borderColor by animateColorAsState(
        targetValue = if (isSelected) {
            MaterialTheme.colorScheme.primary
        } else {
            MaterialTheme.colorScheme.outline.copy(alpha = 0.3f)
        },
        label = "borderColor"
    )
    
    val scale by animateFloatAsState(
        targetValue = if (isSelected) 1.02f else 1f,
        label = "scale"
    )
    
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .scale(scale)
            .clickable { onSelect() },
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(
            width = if (isSelected) 2.dp else 1.dp,
            color = borderColor
        ),
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected) {
                MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
            } else {
                MaterialTheme.colorScheme.surface
            }
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = packageInfo.title,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    
                    // Best value badge
                    if (packageInfo.isBestValue) {
                        Badge(
                            containerColor = MaterialTheme.colorScheme.primary
                        ) {
                            Text(
                                text = "BEST VALUE",
                                modifier = Modifier.padding(horizontal = 4.dp),
                                fontSize = 10.sp
                            )
                        }
                    }
                    
                    // Free trial badge
                    if (packageInfo.hasFreeTrial) {
                        Badge(
                            containerColor = MaterialTheme.colorScheme.tertiary
                        ) {
                            Text(
                                text = "${packageInfo.freeTrialDuration} FREE",
                                modifier = Modifier.padding(horizontal = 4.dp),
                                fontSize = 10.sp
                            )
                        }
                    }
                }
                
                if (packageInfo.pricePerMonth != null) {
                    Text(
                        text = packageInfo.pricePerMonth,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                
                if (packageInfo.savingsPercent != null && packageInfo.savingsPercent > 0) {
                    Text(
                        text = "Save ${packageInfo.savingsPercent}%",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
            
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = packageInfo.priceString,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}
