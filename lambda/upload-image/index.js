/**
 * Lambda 함수: 이미지 업로드
 * 트리거: API Gateway POST /images
 * 역할: JWT 검증 → 파일 검증 → S3 업로드 → imageUrl 반환
 *
 * 참고: DB 작업은 백엔드가 처리 (게시글/프로필 작성 시)
 */

const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { SSMClient, GetParameterCommand } = require('@aws-sdk/client-ssm');

// AWS 클라이언트 초기화
const s3Client = new S3Client({ region: process.env.AWS_REGION });
const ssmClient = new SSMClient({ region: process.env.AWS_REGION });

// Parameter Store 캐시 (Lambda 재사용 시 성능 향상)
let jwtSecretCache = null;

/**
 * Parameter Store에서 JWT_SECRET 가져오기
 */
async function getJwtSecret() {
    if (jwtSecretCache) {
        return jwtSecretCache;
    }

    const response = await ssmClient.send(
        new GetParameterCommand({
            Name: '/community/JWT_SECRET',
            WithDecryption: true  // KMS 복호화
        })
    );

    jwtSecretCache = response.Parameter.Value;
    return jwtSecretCache;
}

/**
 * JWT 검증
 *
 * 지원하는 토큰 타입:
 * 1. User Token (role: USER) - 정식 사용자 토큰
 * 2. Guest Token (role: GUEST) - 회원가입용 임시 토큰 (5분)
 */
async function verifyJWT(token) {
    if (!token) {
        throw new Error('TOKEN_MISSING');
    }

    const jwtSecret = await getJwtSecret();

    try {
        const payload = jwt.verify(token, jwtSecret);
        return {
            userId: payload.sub,
            email: payload.email,
            role: payload.role || 'USER'  // 기본값: USER
        };
    } catch (error) {
        if (error.name === 'TokenExpiredError') {
            throw new Error('TOKEN_EXPIRED');
        }
        throw new Error('TOKEN_INVALID');
    }
}

/**
 * 파일 시그니처(Magic Number) 검증
 */
function validateImageHeader(fileBuffer, contentType) {
    const signatures = {
        'image/jpeg': [0xFF, 0xD8, 0xFF],
        'image/png': [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        'image/gif': [0x47, 0x49, 0x46, 0x38]  // GIF8
    };

    const expectedSignature = signatures[contentType];
    if (!expectedSignature) {
        throw new Error('INVALID_FILE_TYPE');
    }

    // 파일 헤더 검증 (MIME type spoofing 방지)
    for (let i = 0; i < expectedSignature.length; i++) {
        if (fileBuffer[i] !== expectedSignature[i]) {
            throw new Error('INVALID_FILE_SIGNATURE');
        }
    }
}

/**
 * 파일 검증
 */
function validateFile(contentType, fileSize, fileBuffer) {
    // Content-Type 검증
    const allowedTypes = ['image/jpeg', 'image/png', 'image/gif'];
    if (!allowedTypes.includes(contentType)) {
        throw new Error('INVALID_FILE_TYPE');
    }

    // 파일 크기 검증 (5MB)
    const MAX_SIZE = 5 * 1024 * 1024;
    if (fileSize > MAX_SIZE) {
        throw new Error('FILE_TOO_LARGE');
    }

    // Magic Number 검증 (보안 강화)
    validateImageHeader(fileBuffer, contentType);
}

/**
 * S3 업로드
 */
async function uploadToS3(userId, file, contentType) {
    const timestamp = Date.now();
    const uuid = crypto.randomUUID();
    const extension = contentType.split('/')[1]; // jpeg, png, gif
    const s3Key = `users/${userId}/images/${timestamp}-${uuid}.${extension}`;

    await s3Client.send(new PutObjectCommand({
        Bucket: process.env.S3_BUCKET,
        Key: s3Key,
        Body: file,
        ContentType: contentType
    }));

    return `https://${process.env.S3_BUCKET}.s3.${process.env.AWS_REGION}.amazonaws.com/${s3Key}`;
}

/**
 * 파일 메타데이터 생성
 *
 * 참고: DB 저장은 백엔드가 처리
 * - 게시글 작성 시: PostService.createPost()
 * - 프로필 수정 시: UserService.updateProfile()
 */
function createImageMetadata(imageUrl, fileSize, originalFilename) {
    return {
        imageUrl,
        fileSize,
        originalFilename,
        uploadedAt: new Date().toISOString()
    };
}

/**
 * Lambda Handler
 */
exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event, null, 2));

    try {
        // 1. JWT 검증
        const token = (event.headers.authorization || event.headers.Authorization)?.replace('Bearer ', '');
        const { userId, role } = await verifyJWT(token);

        // 2. 역할별 로깅
        if (role === 'GUEST') {
            console.log('✅ Guest Token detected - signup image upload');
        } else {
            console.log('✅ User Token detected - authenticated upload');
        }

        // 3. 파일 검증
        const contentType = event.headers['content-type'] || event.headers['Content-Type'];
        const fileBuffer = Buffer.from(event.body, 'base64');
        const fileSize = fileBuffer.length;

        validateFile(contentType, fileSize, fileBuffer);

        // 4. S3 업로드
        const imageUrl = await uploadToS3(userId, fileBuffer, contentType);

        // 5. 메타데이터 생성
        const originalFilename = event.headers['x-filename'] || `image-${Date.now()}`;
        const metadata = createImageMetadata(imageUrl, fileSize, originalFilename);

        // 6. 응답 (DB 저장은 백엔드가 처리)
        return {
            statusCode: 201,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': process.env.FRONTEND_URL || '*'
            },
            body: JSON.stringify({
                message: 'upload_image_success',
                data: metadata,
                timestamp: new Date().toISOString()
            })
        };

    } catch (error) {
        console.error('Error:', error);

        // 에러 코드 매핑
        const errorMap = {
            'TOKEN_MISSING': { status: 401, code: 'AUTH-003', message: 'Token missing' },
            'TOKEN_EXPIRED': { status: 401, code: 'AUTH-003', message: 'Token has expired' },
            'TOKEN_INVALID': { status: 401, code: 'AUTH-003', message: 'Invalid token' },
            'INVALID_FILE_TYPE': { status: 400, code: 'IMAGE-003', message: 'Invalid file type' },
            'INVALID_FILE_SIGNATURE': { status: 400, code: 'IMAGE-004', message: 'Invalid file signature (MIME type spoofing detected)' },
            'FILE_TOO_LARGE': { status: 413, code: 'IMAGE-002', message: 'File too large' }
        };

        const errorInfo = errorMap[error.message] || {
            status: 500,
            code: 'COMMON-999',
            message: 'Internal server error'
        };

        return {
            statusCode: errorInfo.status,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': process.env.FRONTEND_URL || '*'
            },
            body: JSON.stringify({
                message: errorInfo.code,
                data: {
                    details: errorInfo.message
                },
                timestamp: new Date().toISOString()
            })
        };
    }
};
