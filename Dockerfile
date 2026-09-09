FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY . .
RUN flutter pub get && flutter build web --release

FROM node:20-alpine
RUN npm i -g serve
COPY --from=build /app/build/web /site
CMD ["sh","-c","serve -s /site -l $PORT"]