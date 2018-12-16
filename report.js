#!/usr/bin/env node

const process = require('process')
const fs = require('fs')

const profile_analysis = process.argv[2]
if (!profile_analysis) {
  console.error(`Usage: ${process.argv[0]} /path/to/analysis/data`)
  process.exit(1)
}

let analysis_data = []
const analysis_batches = fs.readdirSync(profile_analysis).forEach((file) => {
  const data = fs.readFileSync(profile_analysis + '/' + file)
  if (data.length > 0) {
    const dataJSON = JSON.parse(data)
    analysis_data = analysis_data.concat(dataJSON)
  }
})

// group by username
let user_data = {}
for (let i = 0; i < analysis_data.length; i++) {
  // sanitize (just in case)
  if (!analysis_data[i].appList) {
    analysis_data[i].appList = []
  }

  user_data[analysis_data[i].name] = analysis_data[i]
}

const all_names = Object.keys(user_data)

// things we're interested in
const num_users = all_names.length;

let num_users_with_social_proof = all_names
  .map((name) => user_data[name].numProofs > 0 ? 1 : 0)
  .reduce((v1, v2) => v1 + v2)

let num_users_with_valid_social_proof = all_names
  .map((name) => user_data[name].validProofs > 0 ? 1 : 0)
  .reduce((v1, v2) => v1 + v2)

let num_users_with_apps = all_names
  .map((name) => user_data[name].appList.length > 0 ? 1 : 0)
  .reduce((v1, v2) => v1 + v2)

let num_users_with_social_proof_nonexpired = all_names
  .map((name) => user_data[name].numProofs > 0 && !user_data[name].expired ? 1 : 0)
  .reduce((v1, v2) => v1 + v2)

let num_users_with_valid_social_proof_nonexpired = all_names
  .map((name) => user_data[name].validProofs > 0 && !user_data[name].expired ? 1 : 0)
  .reduce((v1, v2) => v1 + v2)

let num_users_with_apps_nonexpired = all_names
  .map((name) => user_data[name].appList.length > 0 && !user_data[name].expired ? 1 : 0)
  .reduce((v1, v2) => v1 + v2)

// what apps are people using?
let all_apps = all_names
  .map((name) => user_data[name].appList)
  .reduce((l1, l2) => l1.concat(l2))
  .filter((appName, index, self) => self.indexOf(appName) == index)

let all_apps_public = all_apps
  .filter((appName) => appName.indexOf('localhost') < 0 && appName.indexOf('127.0.0.1') < 0)

let app_usage = {}
all_apps_public.forEach((appName) => {
  app_usage[appName] = all_names
    .filter((name) => user_data[name].appList.indexOf(appName) >= 0)
    .length
})

let app_ranking = []
all_apps_public.forEach((appName) => {
  app_ranking.push({'app': appName, 'users': app_usage[appName]})
})

app_ranking.sort((app1, app2) => app1.users < app2.users ? 1 : (app1.users > app2.users ? -1 : 0))

// how many names have a localhost app?
let names_with_localhost_app = all_names
  .filter((name) => user_data[name].appList
    .map((appName) => appName.indexOf('localhost') >= 0 || appName.indexOf('127.0.0.1') >= 0)
    .reduce((t1, t2) => t1 || t2, false) ? 1 : 0)

console.log(`Number of users: ${num_users}`)
console.log(`Number of users with at least one social proof: ${num_users_with_social_proof}. Non-expired: ${num_users_with_social_proof_nonexpired}`)
console.log(`Number of users with at least one valid social proof: ${num_users_with_valid_social_proof}. Non-expired: ${num_users_with_valid_social_proof_nonexpired}`)
console.log(`Number of users with at least one application: ${num_users_with_apps}.  Non-expired: ${num_users_with_apps_nonexpired}`)
console.log(`Number of unique public apps: ${all_apps.length}`)
console.log(`Number of users with a "localhost" app: ${names_with_localhost_app.length}`)
console.log(`App ranking`)
for (let i = 0; i < (app_ranking.length < 10 ? app_ranking.length : 10); i++) {
  const app = app_ranking[i]
  console.log(`${app.users} ${app.app}`)
}

console.log(JSON.stringify(all_apps_public))
