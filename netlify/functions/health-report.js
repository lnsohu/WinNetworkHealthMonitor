// netlify/functions/health-report/health-report.js
exports.handler = async function(event, context) {
    // 添加 CORS 头
    const headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'POST, OPTIONS'
    };

    // 处理预检请求
    if (event.httpMethod === 'OPTIONS') {
        return {
            statusCode: 200,
            headers,
            body: ''
        };
    }

    if (event.httpMethod !== 'POST') {
        return {
            statusCode: 405,
            headers,
            body: JSON.stringify({ error: 'Method Not Allowed' })
        };
    }
    
    try {
        console.log('Received health report');
        
        let healthData;
        try {
            healthData = JSON.parse(event.body);
        } catch (parseError) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({ error: 'Invalid JSON' })
            };
        }
        
        // 简单的数据验证
        if (!healthData.Device || !healthData.Timestamp) {
            return {
                statusCode: 400,
                headers,
                body: JSON.stringify({ error: 'Missing required fields' })
            };
        }
        
        // 记录接收到的数据
        console.log('Device:', healthData.Device);
        console.log('Location:', healthData.Location);
        console.log('Has Internet:', healthData.InternetConnectivity?.HasInternet);
        console.log('VPN Connected:', healthData.VPNStatus?.Connected);
        
        // 成功响应
        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({ 
                message: 'Health report received successfully',
                device: healthData.Device,
                timestamp: healthData.Timestamp
            })
        };
    } catch (error) {
        console.error('Function error:', error);
        
        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({ 
                error: 'Internal server error',
                details: error.message 
            })
        };
    }
};