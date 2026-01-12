const { greet } = require('./greet.js');

// Test 1: greet("World") should return "Hello, World!"
const result = greet("World");
const expected = "Hello, World!";

if (result === expected) {
  console.log('✓ Test passed: greet("World") returns "Hello, World!"');
} else {
  console.error(`✗ Test failed: Expected "${expected}" but got "${result}"`);
  process.exit(1);
}

console.log('\nAll tests passed! 🎉');
