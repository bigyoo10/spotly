# Spotly 

**Spotly**는 관심 있는 장소를 저장하고 관리할 수 있는 **위치 북마크 앱**입니다.
Google Maps와 Kakao Local API를 활용하여 장소를 검색하고, 폴더와 태그로 정리하여 다시 방문할 수 있도록 설계되었습니다.

Flutter 기반으로 제작된 개인 프로젝트이며 **지도 기반 장소 관리 앱**을 목표로 개발되었습니다.

---

#  주요 기능

###  지도 기반 장소 탐색

* Google Maps 기반 지도 화면
* 위치 검색 및 장소 정보 확인

###  장소 저장

* 관심 있는 장소 저장
* 메모 및 태그 추가 가능

###  폴더 관리

* 저장한 장소를 폴더로 분류
* 여행, 맛집, 카페 등 카테고리 관리

###  즐겨찾기

* 중요 장소 즐겨찾기 표시
* 빠른 접근 가능

### 🗂 방문 기록

* 방문 여부 기록
* 방문 횟수 및 최근 방문일 관리

---

# 🛠 기술 스택

| 구분               | 기술                  |
| ---------------- | ------------------- |
| Framework        | Flutter             |
| State Management | Riverpod            |
| 지도               | Google Maps Flutter |
| 로컬 DB            | Hive                |
| 네트워크             | Dio                 |
| 라우팅              | GoRouter            |
| 장소 검색            | Kakao Local API     |

---

# 📱 앱 화면

*(스크린샷 추가 예정)*

| 지도         | 저장         |
| ---------- | ---------- |
| screenshot | screenshot |

| 폴더         | 상세         |
| ---------- | ---------- |
| screenshot | screenshot |

---

#  실행 방법

### 1️.저장소 클론

```bash
git clone https://github.com/bigyoo10/spotly.git
cd spotly
```

### 2️.패키지 설치

```bash
flutter pub get
```

---

#  API 키 설정

보안 문제로 인해 API 키는 저장소에 포함되어 있지 않습니다.

프로젝트 루트에 `.env` 파일을 생성합니다.

예시

```env
KAKAO_REST_API_KEY=your_kakao_key
GOOGLE_MAPS_API_KEY=your_google_maps_key
```

---

## Android 설정

파일 위치

```
android/local.properties
```

예시

```
MAPS_API_KEY=your_google_maps_key
```

---

## iOS 설정

파일 위치

```
ios/Flutter/keys.xcconfig
```

예시

```
GOOGLE_MAPS_API_KEY=your_google_maps_key
```

---

#  보안 정책

다음 파일은 Git에 포함되지 않습니다.

```
.env
android/local.properties
ios/Flutter/keys.xcconfig
```

API 키 유출 방지를 위해 `.gitignore`에 등록되어 있습니다.

---

#  프로젝트 구조

```
spotly
├── lib
│   ├── core
│   ├── data
│   ├── domain
│   ├── features
│   └── main.dart
│
├── android
├── ios
├── assets
│   └── icon
│
├── pubspec.yaml
└── README.md
```

---

#  개발자

GitHub
https://github.com/bigyoo10

---

#  라이선스

본 프로젝트는 **개인 포트폴리오 및 학습 목적**으로 제작되었습니다.
