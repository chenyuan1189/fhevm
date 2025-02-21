import { mkdirSync, writeFileSync } from 'fs';

import { ALL_OPERATORS, SUPPORTED_BITS, checks } from './common';
import { generateInputVerifiers } from './inputVerifier';
import operatorsPrices from './operatorsPrices.json';
import { generateFHEPayment } from './payments';
import * as t from './templates';
import * as testgen from './testgen';
import { addTFHEExecutorEvents } from './tfheexecutor';

function generateAllFiles() {
  const numSplits = 12;
  const operators = checks(ALL_OPERATORS);
  const [tfheSolSource, overloads] = t.tfheSol(operators, SUPPORTED_BITS, false);
  const ovShards = testgen.splitOverloadsToShards(overloads);
  writeFileSync('lib/Impl.sol', t.implSol(operators));
  writeFileSync('lib/TFHE.sol', tfheSolSource);
  writeFileSync('lib/FHEPayment.sol', generateFHEPayment(operatorsPrices));
  writeFileSync('lib/InputVerifier.native.sol', generateInputVerifiers(false));
  writeFileSync('lib/InputVerifier.coprocessor.sol', generateInputVerifiers(true));
  writeFileSync('lib/TFHEExecutor.events.sol', addTFHEExecutorEvents('lib/TFHEExecutor.sol'));
  writeFileSync('payment/Payment.sol', t.paymentSol());
  mkdirSync('examples/tests', { recursive: true });
  ovShards.forEach((os) => {
    writeFileSync(`examples/tests/TFHETestSuite${os.shardNumber}.sol`, testgen.generateSmartContract(os));
  });
  const tsSplits: string[] = testgen.generateTestCode(ovShards, numSplits);
  tsSplits.forEach((split, splitIdx) => writeFileSync(`test/tfheOperations/tfheOperations${splitIdx + 1}.ts`, split));
}

generateAllFiles();
