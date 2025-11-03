// 临时存储最新数据
let latestData = null;

exports.handler = async function(event, context) {
    const headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Content-Type': 'application/json'
    };

    if (event.httpMethod === 'OPTIONS') {
        return {
            statusCode: 200,
            headers,
            body: ''
        };
    }

    if (event.httpMethod === 'POST') {
        try {
            const requestBody = JSON.parse(event.body);
            console.log('收到完整网络检测数据:', JSON.stringify(requestBody, null, 2));
            
            // 更新临时存储
            latestData = requestBody;
            
            return {
                statusCode: 200,
                headers,
                body: JSON.stringify({ 
                    success: true, 
                    message: '完整数据接收成功',
                    receivedAt: new Date().toISOString()
                })
            };
        } catch (error) {
            console.error('处理数据时出错:', error);
            return {
                statusCode: 500,
                headers,
                body: JSON.stringify({ 
                    success: false, 
                    error: error.message 
                })
            };
        }
    }

    return {
        statusCode: 405,
        headers,
        body: JSON.stringify({ error: '方法不允许' })
    };
};

// 导出 latestData 以便其他函数访问
exports.getLatestData = function() {
    return latestData;
};