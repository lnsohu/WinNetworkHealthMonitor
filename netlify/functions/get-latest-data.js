// 临时存储最新数据（内存中，重启会丢失）
let latestData = null;

exports.handler = async function(event, context) {
    const headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Content-Type': 'application/json'
    };

    if (event.httpMethod === 'OPTIONS') {
        return {
            statusCode: 200,
            headers,
            body: ''
        };
    }

    if (event.httpMethod === 'GET') {
        if (!latestData) {
            return {
                statusCode: 404,
                headers,
                body: JSON.stringify({ 
                    success: false, 
                    message: '暂无数据' 
                })
            };
        }

        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({
                success: true,
                data: latestData,
                lastUpdated: latestData.timestamp
            })
        };
    }

    return {
        statusCode: 405,
        headers,
        body: JSON.stringify({ error: '方法不允许' })
    };
};

// 同时修改 save-data.js 来更新这个临时存储
// 在 save-data.js 顶部添加：
const getLatestData = require('./get-latest-data');

// 然后在 POST 处理中添加：
// latestData = requestBody; // 更新最新数据