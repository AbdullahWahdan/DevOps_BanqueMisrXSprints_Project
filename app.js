const path = require('path');
const express = require('express');
const OS = require('os');
const bodyParser = require('body-parser');
const mongoose = require("mongoose");
const cors = require('cors');
const client = require('prom-client');   // add Prometheus
const axios = require('axios');          // add crible

const app = express();


app.use(bodyParser.json());
app.use(express.static(path.join(__dirname, '/')));
app.use(cors());

// ====== Prometheus Metrics ======
client.collectDefaultMetrics();


// Debug: Log environment variables (without exposing sensitive data)
console.log("MONGO_URI:", process.env.MONGO_URI ? "SET" : "NOT SET");
console.log("MONGO_USERNAME:", process.env.MONGO_USERNAME ? "SET" : "NOT SET");
console.log("MONGO_PASSWORD:", process.env.MONGO_PASSWORD ? "SET" : "NOT SET");

mongoose.connect(process.env.MONGO_URI, {
    user: process.env.MONGO_USERNAME,
    pass: process.env.MONGO_PASSWORD,
    useNewUrlParser: true,
    useUnifiedTopology: true
}, function(err) {
    if (err) {
        console.log("MongoDB error!! " + err)
        sendToCribl({ level: "error", msg: "MongoDB connection failed", error: err.toString() });
    } else {
        console.log("MongoDB Connection Successful")
        sendToCribl({ level: "info", msg: "MongoDB connected successfully" });
    }
});

var Schema = mongoose.Schema;
var dataSchema = new Schema({
    name: String,
    id: Number,
    description: String,
    image: String,
    velocity: String,
    distance: String
});
var planetModel = mongoose.model('planets', dataSchema);


app.post('/planet', function(req, res) {
    planetModel.findOne({ id: req.body.id }, function(err, planetData) {
        if (err) {
            sendToCribl({ level: "error", msg: "Planet lookup failed", error: err.toString() });
            res.status(500).send("Error in Planet Data");
        } else {
            sendToCribl({ level: "info", msg: "Planet data retrieved", planetId: req.body.id });
            res.send(planetData);
        }
    });
});

app.get('/', async (req, res) => {
    res.sendFile(path.join(__dirname, '/', 'index.html'));
});

app.get('/os', function(req, res) {
    res.setHeader('Content-Type', 'application/json');
    res.send({
        "os": OS.hostname(),
        "env": process.env.NODE_ENV
    });
});

app.get('/live', function(req, res) {
    res.json({ "status": "live" });
});

app.get('/ready', function(req, res) {
    res.json({ "status": "ready" });
});

// ====== Prometheus Metrics Endpoint ======
app.get('/metrics', async (req, res) => {
    res.set('Content-Type', client.register.contentType);
    res.end(await client.register.metrics());
});

// ====== Cribl Logger Function ======
function sendToCribl(log) {
    if (!process.env.CRIBL_URL) return; 
    axios.post(process.env.CRIBL_URL, log)
        .catch(err => console.error("Cribl logging failed: " + err));
}


app.listen(3000, () => {
    console.log("Server successfully running on port - " + 3000);
    sendToCribl({ level: "info", msg: "Server started", port: 3000 });
});

module.exports = app;
