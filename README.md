# AES-256 Encryption and Decryption System with Verilog

This project implements an **AES-256 encryption and decryption system using Verilog HDL**. The design provides both encryption and decryption functionality based on the **Advanced Encryption Standard (AES-256)** algorithm.

## Description

The system processes **128-bit plaintext/ciphertext data** using a **256-bit encryption key**. AES-256 uses **14 encryption/decryption rounds** to provide secure data transformation.

### Encryption

The encryption module converts 128-bit plaintext into 128-bit ciphertext through the following operations:

* **SubBytes** – Performs byte substitution using the AES S-Box.
* **ShiftRows** – Performs cyclic row shifting on the AES state matrix.
* **MixColumns** – Applies column transformation using Galois Field arithmetic.
* **AddRoundKey** – XORs the state with the corresponding round key.
* **Key Expansion** – Generates the round keys required for all AES rounds.

### Decryption

The decryption module reverses the encryption process to recover the original plaintext from the ciphertext. It implements the inverse AES transformations:

* **InvSubBytes** – Inverse byte substitution using the inverse S-Box.
* **InvShiftRows** – Performs the inverse row shifting operation.
* **InvMixColumns** – Performs the inverse column transformation.
* **AddRoundKey** – Applies the corresponding round key during decryption.
* **Key Expansion** – Generates and provides the required round keys for the decryption process.

## Features

* AES-256 encryption and decryption
* 128-bit plaintext/ciphertext data
* 256-bit encryption key
* 14 AES rounds
* Verilog HDL implementation
* Separate encryption and decryption modules
* Key expansion for AES-256
* Simulation-based functional verification
* Testbench for encryption and decryption verification
* Comparison with expected AES test vectors

## Verification

A dedicated **Verilog testbench** is developed to verify both encryption and decryption operations. Different plaintext and 256-bit key test vectors are applied to the design.

The generated ciphertext is compared with the expected AES-256 ciphertext. The ciphertext is then passed through the decryption module, and the recovered plaintext is compared with the original input plaintext to verify the complete encryption and decryption process.

```text
Plaintext
    │
    ▼
┌───────────────┐
│ AES-256       │
│ Encryption    │
└───────────────┘
    │
    ▼
Ciphertext
    │
    ▼
┌───────────────┐
│ AES-256       │
│ Decryption    │
└───────────────┘
    │
    ▼
Recovered Plaintext
```

## Project Goal

The main goal of this project is to **design, implement, and verify an AES-256 cryptographic system in Verilog HDL**, while gaining practical experience in RTL design, hardware-based cryptographic algorithms, modular design, and functional verification.
