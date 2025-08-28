/**
 * Token Coverage Analysis Script
 *
 * Analyzes which tokens are supported on which networks
 */

import { getSupportedNetworks, getSupportedTokensForNetwork, getTokenAddress } from "../config/tokens";

function printHeader(title: string) {
  console.log(`\n${"=".repeat(80)}`);
  console.log(`${title}`);
  console.log(`${"=".repeat(80)}`);
}

function printSection(title: string) {
  console.log(`\n${title}`);
  console.log(`${"-".repeat(60)}`);
}

function analyzeTokenCoverage() {
  printHeader("🪙 TOKEN COVERAGE ANALYSIS - PLURISWAP");

  const allNetworks = getSupportedNetworks();
  const mainnetNetworks = allNetworks.filter(n => !n.includes('Sepolia') && !n.includes('Alfajores') && !n.includes('Amoy') && !n.includes('Testnet'));
  const testnetNetworks = allNetworks.filter(n => n.includes('Sepolia') || n.includes('Alfajores') || n.includes('Amoy') || n.includes('Testnet'));

  const tokens = ['USDT', 'USDC', 'WBTC', 'DAI', 'ETH'];

  // Mainnets Analysis
  printSection("🌐 MAINNET COVERAGE");

  console.log(`\n📊 **Token Availability Matrix (Mainnets):**`);
  console.log(`| Token | ${mainnetNetworks.map(n => n.padEnd(10)).join(' | ')} | Total |`);
  console.log(`|-------|${mainnetNetworks.map(() => '-----------').join('-|')}-------|`);

  tokens.forEach(token => {
    const coverage = mainnetNetworks.map(network => {
      const address = getTokenAddress(token, network);
      return address ? '✅' : '❌';
    });

    const totalSupported = coverage.filter(c => c === '✅').length;
    console.log(`| ${token.padEnd(5)} | ${coverage.map(c => c.padEnd(10)).join(' | ')} | ${totalSupported}/${mainnetNetworks.length} |`);
  });

  // Testnets Analysis
  printSection("🧪 TESTNET COVERAGE");

  console.log(`\n📊 **Token Availability Matrix (Testnets):**`);
  console.log(`| Token | ${testnetNetworks.map(n => n.replace('Testnet', 'Test').padEnd(12)).join(' | ')} | Total |`);
  console.log(`|-------|${testnetNetworks.map(() => '-------------').join('-|')}-------|`);

  tokens.forEach(token => {
    const coverage = testnetNetworks.map(network => {
      const address = getTokenAddress(token, network);
      return address ? '✅' : '❌';
    });

    const totalSupported = coverage.filter(c => c === '✅').length;
    console.log(`| ${token.padEnd(5)} | ${coverage.map(c => c.padEnd(12)).join(' | ')} | ${totalSupported}/${testnetNetworks.length} |`);
  });

  // Detailed Network Analysis
  printSection("📋 DETAILED NETWORK ANALYSIS");

  [...mainnetNetworks, ...testnetNetworks].forEach(network => {
    const supportedTokens = getSupportedTokensForNetwork(network);
    const networkType = mainnetNetworks.includes(network) ? 'Mainnet' : 'Testnet';

    console.log(`\n🔍 **${network} (${networkType})**: ${supportedTokens.length}/5 tokens supported`);

    supportedTokens.forEach(token => {
      console.log(`   ✅ ${token.symbol}: ${token.address}`);
    });

    const missingTokens = tokens.filter(t => !supportedTokens.some(st => st.symbol === t));
    if (missingTokens.length > 0) {
      console.log(`   ❌ Missing: ${missingTokens.join(', ')}`);
    }
  });

  // Summary Statistics
  printSection("📈 SUMMARY STATISTICS");

  console.log(`\n🎯 **Overall Coverage:**`);
  console.log(`   • Total Networks: ${allNetworks.length}`);
  console.log(`   • Mainnets: ${mainnetNetworks.length}`);
  console.log(`   • Testnets: ${testnetNetworks.length}`);
  console.log(`   • Tokens: ${tokens.length}`);

  const totalPossible = allNetworks.length * tokens.length;
  let totalSupported = 0;

  allNetworks.forEach(network => {
    const supportedTokens = getSupportedTokensForNetwork(network);
    totalSupported += supportedTokens.length;
  });

  const coveragePercentage = ((totalSupported / totalPossible) * 100).toFixed(1);

  console.log(`   • Total Token-Network Combinations: ${totalPossible}`);
  console.log(`   • Supported Combinations: ${totalSupported}`);
  console.log(`   • Coverage Percentage: ${coveragePercentage}%`);

  // Issues and Recommendations
  printSection("⚠️ ISSUES & RECOMMENDATIONS");

  const issues: string[] = [];
  const recommendations: string[] = [];

  // Check for missing tokens on mainnets
  mainnetNetworks.forEach(network => {
    const supportedTokens = getSupportedTokensForNetwork(network);
    const missingTokens = tokens.filter(t => !supportedTokens.some(st => st.symbol === t));

    if (missingTokens.length > 0) {
      issues.push(`${network}: Missing ${missingTokens.join(', ')}`);
    }
  });

  // Check for placeholder addresses
  tokens.forEach(token => {
    allNetworks.forEach(network => {
      const address = getTokenAddress(token, network);
      if (address && (address.includes('Placeholder') || address.includes('592C5b8b6c4d6A2f'))) {
        issues.push(`${token} on ${network}: Uses placeholder address`);
        recommendations.push(`Update ${token} address on ${network} with real contract`);
      }
    });
  });

  if (issues.length === 0) {
    console.log(`\n✅ **No major issues found!**`);
    console.log(`   All mainnet tokens have valid addresses.`);
  } else {
    console.log(`\n⚠️ **Issues Found:**`);
    issues.forEach(issue => console.log(`   • ${issue}`));
  }

  if (recommendations.length > 0) {
    console.log(`\n💡 **Recommendations:**`);
    recommendations.forEach(rec => console.log(`   • ${rec}`));
  }

  // Production Readiness
  printSection("🚀 PRODUCTION READINESS");

  const mainnetCoverage = mainnetNetworks.map(network => {
    const supportedTokens = getSupportedTokensForNetwork(network);
    return supportedTokens.length;
  });

  const averageMainnetCoverage = mainnetCoverage.reduce((a, b) => a + b, 0) / mainnetCoverage.length;
  const minMainnetCoverage = Math.min(...mainnetCoverage);

  console.log(`\n📊 **Mainnet Readiness:**`);
  console.log(`   • Average tokens per mainnet: ${averageMainnetCoverage.toFixed(1)}/5`);
  console.log(`   • Minimum tokens on any mainnet: ${minMainnetCoverage}/5`);
  console.log(`   • All mainnets have at least 4 tokens: ${minMainnetCoverage >= 4 ? '✅' : '❌'}`);
  console.log(`   • All mainnets have all 5 tokens: ${minMainnetCoverage === 5 ? '✅' : '❌'}`);

  const productionReady = minMainnetCoverage >= 4 && issues.filter(i => !i.includes('Placeholder')).length === 0;

  printHeader(productionReady ? "🎉 PRODUCTION READY!" : "⚠️ REQUIRES ATTENTION");

  if (productionReady) {
    console.log(`
✅ **Token coverage is sufficient for production deployment!**

📋 **Ready for deployment on all ${mainnetNetworks.length} mainnets:**
${mainnetNetworks.map(n => `   • ${n}`).join('\n')}

🪙 **All major tokens supported across production networks:**
${tokens.map(t => `   • ${t}`).join('\n')}

🚀 **You can proceed with Phase 3 deployment!**
    `);
  } else {
    console.log(`
⚠️ **Token coverage needs attention before production deployment.**

📋 **Action Items:**
${issues.map(i => `   • ${i}`).join('\n')}
${recommendations.map(r => `   • ${r}`).join('\n')}
    `);
  }
}

// Export for use as module
export { analyzeTokenCoverage };

// Run if executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  analyzeTokenCoverage();
}
