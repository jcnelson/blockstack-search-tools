#!/usr/bin/env node
const bsk = require('blockstack')
const fs = require('fs')
const process = require('process')

// read profile from stdin
let profilesJSON = fs.readFileSync('/dev/stdin', 'utf-8')
let profiles = JSON.parse(profilesJSON)

SERVICES = ['twitter', 'facebook', 'hackernews', 'instagram', 'github']

function checkExpired(fqu) {
  return fetch(`http://localhost:6270/v1/names/${fqu}`)
    .then((x) => {
      if (x.statusCode == 404) {
        return true;
      }
      else {
        return false;
      }
    })
}

function getNumSocialProofs(profile) {
  return Promise.resolve().then(() => {
    if (profile && profile.account) {
      return profile.account.length;
    }
    else {
      return 0;
    }
  })
}

function checkSocialProofs(fqu, address, profile) {
  if (profile && profile.account && profile.account.filter(x => SERVICES.indexOf(x.service.toLowerCase()) >= 0).length > 0) {
    return bsk.validateProofs(profile, address, fqu)
      .then(proofs => proofs.filter(x => x.valid).length)
      .catch(err => 0)
  } else {
    return Promise.resolve().then(() => 0)
  }
}

function checkAppInstalls(profile) {
  let count = 0
  if (profile && profile.apps) {
    count = Object.keys(profile.apps).length;
  }
  return Promise.resolve().then(() => count)
}

function checkAppList(profile) {
  let appsList = []
  if (profile && profile.apps) {
    appsList = Object.keys(profile.apps)
    if (!appsList) {
      appsList = []
    }
  }
  return Promise.resolve().then(() => appsList)
}

function checkProfile(fqu, address, profile) {
  return Promise.all([
    checkExpired(fqu),
    getNumSocialProofs(profile),
    checkSocialProofs(fqu, address, profile),
    checkAppInstalls(profile),
    checkAppList(profile)
  ])
  .then(([
    expired,
    numSocialProofs,
    validProofsCount,
    appUseCount,
    appList
  ]) => {
    const ret = {
      name: fqu,
      address: address,
      expired: expired,
      numProofs: numSocialProofs,
      validProofs: validProofsCount,
      apps: appUseCount,
      appList: appList
    };
    return ret
  })
}

Promise.all(profiles.map(({name, address, profile}) => {
  return checkProfile(name, address, profile)
}))
.then((metadata) => {
  console.log(JSON.stringify(metadata))
})

