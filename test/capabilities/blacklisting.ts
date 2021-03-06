import { Client, Provider, ProviderRegistry } from "@blockstack/clarity"
import { assert } from "chai"
import Accounts from '../accounts'
import TokenHelper from '../../src/TokenHelper'
import { createCheckAndDeploy } from "../setup"

describe("Tokensoft Token burning capability", () => {
  let provider: Provider
  let tokensoftTokenClient: Client

  before(async () => {
    provider = await ProviderRegistry.createProvider()
    await createCheckAndDeploy(`${Accounts.alice}.ft-trait`, 'ft-trait', provider)
    await createCheckAndDeploy(`${Accounts.alice}.restricted-token-trait`, 'restricted-token-trait', provider)
    await createCheckAndDeploy(`${Accounts.alice}.metadata-uri-token-trait`, 'metadata-uri-token-trait', provider)
    tokensoftTokenClient = await createCheckAndDeploy(`${Accounts.alice}.tokensoft-token`, "tokensoft-token", provider)
    await TokenHelper.Meta.initialize(
      tokensoftTokenClient,
      "Tokensoft Token",
      "TSFT",
      8,
      Accounts.alice,
      Accounts.alice
    )
  })

  it("should not be able to update blacklist without role", async () => {
    try {
      await TokenHelper.Capabilities.updateBlacklist(
        tokensoftTokenClient,
        Accounts.bob,
        true,
        Accounts.alice
      )
      assert.fail('should not allow update')
    }catch{}
    
    // Give alice the capability to burn
    await TokenHelper.Roles.addToRole(
      tokensoftTokenClient,
      TokenHelper.Roles.ROLE_TYPES.BLACKLISTER,
      Accounts.alice,
      Accounts.alice
    )

    assert.equal(await TokenHelper.Capabilities.isBlacklisted(tokensoftTokenClient, Accounts.bob), 'false')

    await TokenHelper.Capabilities.updateBlacklist(
      tokensoftTokenClient,
      Accounts.bob,
      true,
      Accounts.alice
    )

    assert.equal(await TokenHelper.Capabilities.isBlacklisted(tokensoftTokenClient, Accounts.bob), 'true')

    await TokenHelper.Capabilities.updateBlacklist(
      tokensoftTokenClient,
      Accounts.bob,
      false,
      Accounts.alice
    )

    assert.equal(await TokenHelper.Capabilities.isBlacklisted(tokensoftTokenClient, Accounts.bob), 'false')
  })

  it("should check all transfer permutations", async () => {

    // Mint bob 100 tokens
    await TokenHelper.Roles.addToRole(
      tokensoftTokenClient,
      TokenHelper.Roles.ROLE_TYPES.MINTER,
      Accounts.alice,
      Accounts.alice
    )
    await TokenHelper.Capabilities.mintTokens(
      tokensoftTokenClient,
      100,
      Accounts.bob,
      Accounts.alice
    )

    // Verify no restrictions
    assert.equal(await TokenHelper.Capabilities.detectTransferRestriction(
      tokensoftTokenClient, 
      100,
      Accounts.bob,
      Accounts.carol), 
    TokenHelper.Capabilities.TRANSFER_RESTRICTIONS.SUCCESS.errorCode)

    // Verify transfer works
    await TokenHelper.Capabilities.transfer(
      tokensoftTokenClient,
      10,
      Accounts.bob,
      Accounts.carol,
      Accounts.bob
    )

    // Add Bob to the blacklist
    await TokenHelper.Capabilities.updateBlacklist(
      tokensoftTokenClient,
      Accounts.bob,
      true,
      Accounts.alice
    )

    assert.equal(await TokenHelper.Capabilities.detectTransferRestriction(
      tokensoftTokenClient, 
      100,
      Accounts.bob,
      Accounts.carol), 
    TokenHelper.Capabilities.TRANSFER_RESTRICTIONS.BLACKLIST.errorCode)

    // Verify tx fails
    try {
      await TokenHelper.Capabilities.transfer(
        tokensoftTokenClient,
        10,
        Accounts.bob,
        Accounts.carol,
        Accounts.bob
      )
      assert.fail('transfer should fail')
    }catch{}

    // Add Carol too
    await TokenHelper.Capabilities.updateBlacklist(
      tokensoftTokenClient,
      Accounts.carol,
      true,
      Accounts.alice
    )

    assert.equal(await TokenHelper.Capabilities.detectTransferRestriction(
      tokensoftTokenClient, 
      100,
      Accounts.bob,
      Accounts.carol), 
    TokenHelper.Capabilities.TRANSFER_RESTRICTIONS.BLACKLIST.errorCode)

    // Verify tx fails
    try {
      await TokenHelper.Capabilities.transfer(
        tokensoftTokenClient,
        10,
        Accounts.bob,
        Accounts.carol,
        Accounts.bob
      )
      assert.fail('transfer should fail')
    }catch{}

    // Remove bob so only Carol is on the list
    await TokenHelper.Capabilities.updateBlacklist(
      tokensoftTokenClient,
      Accounts.bob,
      false,
      Accounts.alice
    )

    assert.equal(await TokenHelper.Capabilities.detectTransferRestriction(
      tokensoftTokenClient, 
      100,
      Accounts.bob,
      Accounts.carol), 
    TokenHelper.Capabilities.TRANSFER_RESTRICTIONS.BLACKLIST.errorCode)

    // Verify tx fails
    try {
      await TokenHelper.Capabilities.transfer(
        tokensoftTokenClient,
        10,
        Accounts.bob,
        Accounts.carol,
        Accounts.bob
      )
      assert.fail('transfer should fail')
    }catch{}

    // Remove carol
    await TokenHelper.Capabilities.updateBlacklist(
      tokensoftTokenClient,
      Accounts.carol,
      false,
      Accounts.alice
    )

    assert.equal(await TokenHelper.Capabilities.detectTransferRestriction(
      tokensoftTokenClient, 
      100,
      Accounts.bob,
      Accounts.carol), 
    TokenHelper.Capabilities.TRANSFER_RESTRICTIONS.SUCCESS.errorCode)

    await TokenHelper.Capabilities.transfer(
      tokensoftTokenClient,
      10,
      Accounts.bob,
      Accounts.carol,
      Accounts.bob
    )

    // Verify amounts
    assert.equal(await TokenHelper.Meta.balanceOf(tokensoftTokenClient, Accounts.bob), 80)
    assert.equal(await TokenHelper.Meta.balanceOf(tokensoftTokenClient, Accounts.carol), 20)

  })

  it("should validate restriction messages", async () => {
    assert.equal(await TokenHelper.Capabilities.messageForRestriction(
      tokensoftTokenClient,      
      TokenHelper.Capabilities.TRANSFER_RESTRICTIONS.SUCCESS.errorCode),
      TokenHelper.Capabilities.TRANSFER_RESTRICTIONS.SUCCESS.message)

    assert.equal(await TokenHelper.Capabilities.messageForRestriction(
      tokensoftTokenClient,      
      TokenHelper.Capabilities.TRANSFER_RESTRICTIONS.BLACKLIST.errorCode),
      TokenHelper.Capabilities.TRANSFER_RESTRICTIONS.BLACKLIST.message)

    assert.equal(await TokenHelper.Capabilities.messageForRestriction(
      tokensoftTokenClient,      
      2),
      TokenHelper.Capabilities.TRANSFER_RESTRICTIONS.UNKNOWN.message)
    
    assert.equal(await TokenHelper.Capabilities.messageForRestriction(
      tokensoftTokenClient,      
      10000),
      TokenHelper.Capabilities.TRANSFER_RESTRICTIONS.UNKNOWN.message)
  })

  after(async () => {
    await provider.close()
  })
})
