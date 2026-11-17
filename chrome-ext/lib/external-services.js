// 외부 서비스(공직메일 등) 목록과 주소 검증. 비밀번호는 이 브라우저에만 저장한다.
export const DEFAULT_EXTERNAL_SERVICES = [
  {
    id: 'official-mail',
    name: '공직메일',
    domain: 'https://mail.korea.kr/',
    method: 'certificate'
  }
];

export function normalizeServiceUrl(input) {
  let url;
  try {
    url = new URL(String(input || '').trim());
  } catch (_) {
    throw new Error('도메인을 http:// 또는 https://로 시작하는 주소로 입력하세요.');
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new Error('도메인은 http:// 또는 https:// 주소만 사용할 수 있습니다.');
  }
  if (url.username || url.password) throw new Error('주소에 아이디·비밀번호를 넣지 마세요.');
  return url;
}

export function normalizeService(service) {
  if (!service || typeof service !== 'object') throw new Error('서비스 정보가 올바르지 않습니다.');
  const name = String(service.name || '').trim();
  if (!name) throw new Error('서비스명을 입력하세요.');
  const url = normalizeServiceUrl(service.domain);
  const method = service.method === 'certificate' ? 'certificate' : 'password';
  const result = {
    id: String(service.id || ('svc_' + Date.now().toString(36))),
    name,
    domain: url.href,
    method
  };
  if (method === 'password') {
    result.userId = String(service.userId || '');
    result.password = String(service.password || '');
  }
  return result;
}
